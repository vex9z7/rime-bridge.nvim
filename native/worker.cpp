// Single-session system-Rime worker; no editor or input-scheme policy here.
#include <rime_api.h>
#include <nlohmann/json.hpp>
#include <dlfcn.h>
#include <fcntl.h>
#include <sys/file.h>
#include <unistd.h>
#include <climits>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>

using json = nlohmann::json;
namespace fs = std::filesystem;
static constexpr size_t max_frame = 65536;
static void require(bool ok, const std::string& why) {
  if (!ok) throw std::runtime_error(why);
}
static std::string string_field(const json& q, const char* name) {
  auto value = q.at(name).get<std::string>();
  require(!value.empty() && value.find('\0') == std::string::npos, std::string("invalid ") + name);
  return value;
}
static int number(const json& q, const char* name, int low = 0) {
  require(q.at(name).is_number_integer(), std::string("integer required: ") + name);
  auto n = q.at(name).get<int64_t>();
  require(n >= low && n <= INT_MAX, std::string("out of range: ") + name);
  return static_cast<int>(n);
}
static std::string str(const char* s) { return s ? s : ""; }

struct Engine {
  RimeApi* api = rime_get_api();
  RimeSessionId session = 0;
  int lock = -1;
  bool initialized = false, attempted = false;
  int generation = 0;
  std::string shared = "/usr/share/rime-data", user, library, plugin;
  bool lua = false;
  const char* modules[5] = {"core", "dict", "gears", "lua", nullptr};
  RimeTraits traits{};

  Engine() {
// Older official headers lack RIME_PROVIDED: check table bounds before access.
#define CHECK(member) require((api && api->data_size >= 0 && \
    sizeof(api->data_size) + static_cast<size_t>(api->data_size) >= \
    offsetof(RimeApi, member) + sizeof(api->member) && api->member), \
    "missing Rime API: " #member)
    CHECK(setup); CHECK(initialize); CHECK(finalize); CHECK(deployer_initialize);
    CHECK(deploy); CHECK(create_session); CHECK(destroy_session);
    CHECK(process_key); CHECK(clear_composition); CHECK(get_context); CHECK(free_context);
    CHECK(get_commit); CHECK(free_commit); CHECK(get_schema_list); CHECK(free_schema_list);
    CHECK(select_schema); CHECK(get_current_schema); CHECK(set_option);
    CHECK(select_candidate_on_current_page); CHECK(get_version); CHECK(find_module);
#undef CHECK
    Dl_info loaded{};
    require(dladdr(reinterpret_cast<void*>(rime_get_api), &loaded) != 0,
            "cannot locate loaded system librime");
    library = fs::canonical(loaded.dli_fname).string();
  }
  ~Engine() {
    close_session();
    if (initialized) api->finalize();
    if (lock >= 0) ::close(lock); // OS releases the lock even after a crash.
  }
  void close_session() {
    if (session) api->destroy_session(session);
    session = 0;
  }
  void new_session() {
    session = api->create_session();
    require(session != 0, "cannot create session; inspect stderr");
  }
  void init(const json& q) {
    require(!attempted, "init allowed once per worker; restart after failure");
    attempted = true;
    if (q.contains("shared_dir")) shared = string_field(q, "shared_dir");
    require(fs::path(shared).is_absolute() && fs::is_directory(shared),
            "shared_dir must be an existing absolute Rime data directory: " + shared);
    shared = fs::canonical(shared).string();
    if (q.contains("lua_plugin")) {
      plugin = string_field(q, "lua_plugin");
      require(fs::path(plugin).is_absolute() && fs::is_regular_file(plugin),
              "lua_plugin must be an existing absolute library path: " + plugin);
      // Explicit trusted system extension; never unload before engine finalization.
      if (!dlopen(plugin.c_str(), RTLD_NOW | RTLD_GLOBAL)) {
        auto error = dlerror();
        throw std::runtime_error("cannot load Lua extension: " + str(error));
      }
      plugin = fs::canonical(plugin).string();
    }
    auto requested = fs::path(string_field(q, "user_dir"));
    require(requested.is_absolute(), "user_dir must be absolute");
    fs::create_directories(requested);
    user = fs::canonical(requested).string();
    auto path = fs::path(user) / ".rime-input.lock";
    lock = ::open(path.c_str(), O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0600);
    require(lock >= 0, "cannot open user directory lock");
    require(flock(lock, LOCK_EX | LOCK_NB) == 0, "user directory busy (one writer only)");
    RIME_STRUCT_INIT(RimeTraits, traits);
    traits.shared_data_dir = shared.c_str();
    traits.user_data_dir = user.c_str();
    traits.distribution_name = "Rime Input";
    traits.distribution_code_name = "rime-input";
    traits.distribution_version = RIME_INPUT_VERSION;
    traits.app_name = "rime.input";
    traits.log_dir = "";
    traits.min_log_level = 2;
    traits.modules = modules;
    api->setup(&traits);
    lua = api->find_module("lua") != nullptr;
    require(!q.value("require_lua", false) || lua,
            "Lua module unavailable; install a compatible extension and set lua_plugin if needed");
    if (!lua) modules[3] = nullptr;
    api->initialize(&traits);
    initialized = true;
    // Deployer modules are separate from normal input modules.
    auto deploy_traits = traits;
    deploy_traits.modules = nullptr;
    api->deployer_initialize(&deploy_traits);
    new_session();
  }
  json info() {
    return {{"protocol", 1}, {"runtime", RIME_INPUT_VERSION},
            {"engine", api->get_version()}, {"extensions", lua ? json::array({"lua"}) : json::array()},
            {"library", library}, {"lua_plugin", plugin},
            {"shared_dir", shared}, {"user_dir", user}};
  }
  json context(bool handled) {
    json out = {{"handled", handled}, {"commit", ""}, {"preedit", ""},
                {"candidates", json::array()}, {"page", 0}, {"selected", 0}};
    RimeContext ctx{}; RIME_STRUCT_INIT(RimeContext, ctx);
    require(api->get_context(session, &ctx), "cannot retrieve context");
    try {
      out["preedit"] = str(ctx.composition.preedit);
      out["page"] = ctx.menu.page_no;
      out["selected"] = ctx.menu.highlighted_candidate_index;
      out["last_page"] = bool(ctx.menu.is_last_page);
      for (int i = 0; i < ctx.menu.num_candidates; ++i)
        out["candidates"].push_back({{"text", str(ctx.menu.candidates[i].text)},
                                    {"comment", str(ctx.menu.candidates[i].comment)}});
    } catch (...) { api->free_context(&ctx); throw; }
    api->free_context(&ctx);
    RimeCommit commit{}; RIME_STRUCT_INIT(RimeCommit, commit);
    if (api->get_commit(session, &commit)) {
      try { out["commit"] = str(commit.text); }
      catch (...) { api->free_commit(&commit); throw; }
      api->free_commit(&commit);
    }
    return out;
  }
  json run(const json& q) {
    auto op = string_field(q, "op");
    int gen = number(q, "generation");
    if (op == "init") { init(q); generation = gen; return info(); }
    require(initialized && session, "engine not initialized");
    if (op == "clear") {
      require(gen >= generation, "stale generation");
      generation = gen;
      api->clear_composition(session);
      return context(true);
    }
    require(gen == generation, "generation mismatch; clear before new input");
    if (op == "info") return info();
    if (op == "deploy") {
      close_session();
      bool ok = api->deploy();
      // Lua modules can cache rime.lua: recreate engine state after deployment.
      api->finalize();
      api->initialize(&traits);
      auto deploy_traits = traits;
      deploy_traits.modules = nullptr;
      api->deployer_initialize(&deploy_traits);
      new_session();
      require(ok, "deployment failed; inspect stderr for schema/component errors");
      return info();
    }
    if (op == "schemas") {
      RimeSchemaList list{};
      require(api->get_schema_list(&list), "cannot list deployed schemas");
      json out = json::array();
      try {
        for (size_t i = 0; i < list.size; ++i)
          out.push_back({{"id", str(list.list[i].schema_id)}, {"name", str(list.list[i].name)}});
      } catch (...) { api->free_schema_list(&list); throw; }
      api->free_schema_list(&list);
      return out;
    }
    if (op == "schema") {
      auto name = string_field(q, "schema");
      RimeSchemaList list{};
      require(api->get_schema_list(&list), "cannot list deployed schemas");
      bool found = false;
      for (size_t i = 0; i < list.size; ++i)
        if (name == str(list.list[i].schema_id)) found = true;
      api->free_schema_list(&list);
      require(found, "schema is not in deployed schema_list: " + name);
      require(api->select_schema(session, name.c_str()), "cannot select schema: " + name);
      api->set_option(session, "ascii_mode", False);
      return context(true);
    }
    if (op == "key")
      return context(api->process_key(session, number(q, "key"),
                                      q.contains("mask") ? number(q, "mask") : 0));
    if (op == "select")
      return context(api->select_candidate_on_current_page(session, number(q, "index")));
    throw std::runtime_error("unknown operation: " + op);
  }
};

int main() {
  try {
    Engine engine;
    int last_id = -1;
    std::string line;
    while (true) {
      line.clear();
      char ch = 0;
      while (std::cin.get(ch) && ch != '\n') {
        require(line.size() < max_frame, "frame exceeds 64 KiB");
        line.push_back(ch);
      }
      if (!std::cin && line.empty()) break;
      require(ch == '\n', "unterminated frame");
      json response = {{"id", nullptr}, {"generation", nullptr}, {"ok", false}};
      bool shutdown = false;
      try {
        auto q = json::parse(line);
        require(q.is_object(), "request must be an object");
        int id = number(q, "id");
        int gen = number(q, "generation");
        response["id"] = id; response["generation"] = gen;
        require(id > last_id, "request IDs must strictly increase");
        last_id = id;
        shutdown = string_field(q, "op") == "shutdown";
        response["result"] = shutdown ? json::object() : engine.run(q);
        response["ok"] = true;
      } catch (const std::exception& e) { response["error"] = e.what(); }
      auto frame = response.dump(-1, ' ', false, json::error_handler_t::replace);
      require(frame.size() <= max_frame, "response exceeds 64 KiB");
      std::cout << frame << '\n' << std::flush;
      if (!std::cout || shutdown) break;
    }
  } catch (const std::exception& e) {
    std::cerr << "portable-rime: " << e.what() << '\n';
    return 1;
  }
}
