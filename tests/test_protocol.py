"""Standalone checks: these are protocol tests, NOT editor key simulation."""
import atexit
import json
import os
from pathlib import Path
import selectors
import subprocess
import sys
import tempfile
import time

worker = str(Path(sys.argv[1]).resolve())
with_lua = "--no-lua" not in sys.argv[2:]
class Client:
    def __init__(self, user):
        self.log = tempfile.TemporaryFile(mode="w+")
        self.p = subprocess.Popen([worker], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=self.log, text=True, bufsize=1)
        atexit.register(self.cleanup)
        self.seq = 0
        self.gen = 0
        self.user = str(user)
        self.timings = []

    def cleanup(self):
        if self.p.poll() is None:
            self.p.terminate()
            try:
                self.p.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.p.kill()
                self.p.wait()
        self.log.close()

    def call(self, op, ok=True, split=False, **args):
        self.seq += 1
        q = dict(id=self.seq, generation=self.gen, op=op, **args)
        line = json.dumps(q) + "\n"
        start = time.monotonic()
        if split:
            self.p.stdin.write(line[:3]); self.p.stdin.flush()
            time.sleep(.01)
            line = line[3:]
        self.p.stdin.write(line); self.p.stdin.flush()
        with selectors.DefaultSelector() as sel:
            sel.register(self.p.stdout, selectors.EVENT_READ)
            if not sel.select(30):
                raise AssertionError("worker response timeout")
        answer = self.p.stdout.readline()
        if not answer:
            self.log.seek(0)
            raise AssertionError(self.log.read())
        r = json.loads(answer)
        if r["ok"] != ok:
            self.log.seek(0)
            print(self.log.read(), file=sys.stderr)
        assert (r["id"], r["generation"], r["ok"]) == (self.seq, self.gen, ok), r
        if op == "key":
            self.timings.append((time.monotonic()-start)*1000)
        return r.get("result") if ok else r["error"]

    def init(self, **kw):
        args = {"require_lua": with_lua}
        if with_lua and os.environ.get("RIME_LUA_PLUGIN"):
            args["lua_plugin"] = os.environ["RIME_LUA_PLUGIN"]
        args.update(kw)
        return self.call("init", user_dir=self.user, **args)

    def close(self):
        if self.p.poll() is None:
            self.call("shutdown")
        assert self.p.wait(timeout=10) == 0
        self.log.close()

    def type(self, text):
        for key in text:
            r = self.call("key", key=ord(key))
        return r

with tempfile.TemporaryDirectory(prefix="rime-bridge-test-") as tmp:
    user = Path(tmp)
    custom = user / "default.custom.yaml"
    custom.write_text("patch:\n  schema_list:\n    - schema: luna_pinyin_simp\n")
    original = custom.read_bytes()
    for args, message in [({"shared_dir": str(user / "missing")}, "shared_dir"),
                          ({"lua_plugin": str(user / "missing.so")}, "lua_plugin")]:
        bad = Client(user)
        assert message in bad.init(ok=False, **args)
        bad.close()
    # Malformed initialization must not create a directory or acquire its lock.
    untouched = user / "invalid-init"
    bad = Client(untouched)
    error = bad.init(ok=False, require_lua="PRIVATE_INIT_VALUE")
    assert error == "invalid JSON request or field type", error
    assert not untouched.exists()
    assert "not initialized" in bad.call("info", ok=False)
    bad.close()
    # A plain process can report a missing Lua module without touching the UI.
    plain = Client(user)
    available = plain.call("init", user_dir=plain.user)
    plain.close()
    if "lua" not in available["extensions"]:
        missing = Client(user)
        assert "Lua module unavailable" in missing.call(
            "init", ok=False, user_dir=missing.user, require_lua=True)
        missing.close()
    c = Client(user)
    info = c.init(split=True)
    if with_lua:
        assert "lua" in info["extensions"], info
    started = time.monotonic()
    c.call("deploy")
    deploy_ms = (time.monotonic() - started) * 1000
    schemas = c.call("schemas")
    assert any(s["id"] == "luna_pinyin_simp" for s in schemas), schemas
    c.call("schema", schema="luna_pinyin_simp")
    r = c.type("nihao")
    assert r["preedit"] and any(x["text"] == "你好" for x in r["candidates"]), r
    assert r["commit"] == "", r
    r = c.call("select", index=0)
    assert r["commit"] == "你好", r
    assert c.call("key", key=ord("n"))["commit"] == ""
    c.gen += 1
    assert c.call("clear")["preedit"] == ""
    second = Client(user)
    assert "busy" in second.init(ok=False)
    second.close()
    for key in [-1, True, None, "PRIVATE_KEY_VALUE", 1.5, 2**64 - 1]:
        error = c.call("key", key=key, ok=False)
        assert "PRIVATE_KEY_VALUE" not in error
    assert "invalid JSON" in c.call("select", ok=False)
    assert "out of range" in c.call("select", index=-1, ok=False)
    c.call("schema", schema="does_not_exist", ok=False)
    c.gen -= 1
    c.call("key", key=ord("n"), ok=False)
    c.gen += 1
    assert c.type("nihao")["preedit"]
    assert c.call("key", key=32)["commit"] == "你好"
    # Exercise conversion data: traditional/simplified are not identical here.
    converted = c.type("hanyu")
    index = next(i for i, item in enumerate(converted["candidates"]) if item["text"] == "汉语")
    assert c.call("select", index=index)["commit"] == "汉语"
    # User-owned scheme, dictionary, custom patch and real Lua translator.
    (user / "fixture.schema.yaml").write_text("""schema:
  schema_id: fixture
  name: User fixture
  version: "1"
engine:
  processors: [speller, selector, express_editor]
  segmentors: [abc_segmentor]
  translators: [lua_translator@fixture, table_translator]
speller:
  alphabet: abcdefghijklmnopqrstuvwxyz
translator:
  dictionary: fixture
  enable_sentence: false
""")
    if not with_lua:
        schema = user / "fixture.schema.yaml"
        schema.write_text(schema.read_text().replace("lua_translator@fixture, ", ""))
    (user / "fixture.dict.yaml").write_text("---\nname: fixture\nversion: '1'\nsort: original\n...\n用户词库\tnihao\t100\n你\tni\t100\n好\thao\t100\n一\tyi\t100\n二\ter\t100\n三\tsan\t100\n")
    (user / "rime.lua").write_text("""function fixture(input, seg)
  if input == "lua" then
    yield(Candidate("fixture", seg.start, seg._end, "脚本候选", "user Lua"))
  end
end
""")
    (user / "fixture.custom.yaml").write_text("patch:\n  menu/page_size: 3\n")
    # Old system Rime compares configuration mtimes at whole-second precision.
    # Advance the edited fixture explicitly rather than sleeping/retrying a test.
    previous_mtime = custom.stat().st_mtime
    custom.write_text("patch:\n  schema_list:\n    - schema: luna_pinyin_simp\n    - schema: fixture\n")
    os.utime(custom, (previous_mtime + 2, previous_mtime + 2))
    original = custom.read_bytes()
    c.call("deploy")
    c.call("schema", schema="fixture")
    assert c.type("nihao")["candidates"][0]["text"] == "用户词库"
    assert c.call("select", index=0)["commit"] == "用户词库"
    if with_lua:
        assert c.type("lua")["candidates"][0]["text"] == "脚本候选"
        assert c.call("select", index=0)["commit"] == "脚本候选"
    c.call("schema", schema="luna_pinyin_simp")
    timings = c.timings[:]
    peak_rss = next(line for line in Path(f"/proc/{c.p.pid}/status").read_text().splitlines() if line.startswith("VmHWM:"))
    c.close()
    assert custom.read_bytes() == original
    assert list(user.glob("*.userdb")), list(user.iterdir())
    c = Client(user)
    c.init()
    c.call("schema", schema="luna_pinyin_simp")
    assert c.type("nihao")["candidates"][0]["text"] == "你好"
    c.call("clear")
    c.close()
    assert custom.read_bytes() == original
    # Deployment errors are explicit and user edits are not replaced.
    broken = user / "fixture.schema.yaml"
    saved = broken.read_bytes()
    previous_mtime = broken.stat().st_mtime
    broken.write_text("schema: [invalid YAML")
    os.utime(broken, (previous_mtime + 2, previous_mtime + 2))
    c = Client(user)
    c.init()
    assert "deployment failed" in c.call("deploy", ok=False)
    assert broken.read_text() == "schema: [invalid YAML"
    broken.write_bytes(saved)
    os.utime(broken, (previous_mtime + 4, previous_mtime + 4))
    c.call("deploy")
    c.close()
    # Invalid JSON must be framed as an error, without poisoning the next request.
    c = Client(user)
    for malformed in ['{"PRIVATE_INPUT":', 'null', '[]', '{"id":true,"generation":0,"op":"info"}']:
        c.p.stdin.write(malformed + "\n"); c.p.stdin.flush()
        response = json.loads(c.p.stdout.readline())
        assert response["ok"] is False
        assert "PRIVATE_INPUT" not in json.dumps(response)
    c.init()
    # Multiple requests delivered in one pipe write retain their ordering.
    c.p.stdin.write(json.dumps(dict(id=2, generation=0, op="info")) + "\n" +
                    json.dumps(dict(id=3, generation=0, op="info")) + "\n")
    c.p.stdin.flush()
    assert json.loads(c.p.stdout.readline())["id"] == 2
    assert json.loads(c.p.stdout.readline())["id"] == 3
    c.seq = 3
    c.close()
    # Oversized input exits without buffering an unbounded line.
    p = subprocess.run([worker], input="x"*65538+"\n", text=True, capture_output=True, timeout=10)
    assert p.returncode == 1 and "64 KiB" in p.stderr
    p = subprocess.run([worker], input='{"id":0', text=True, capture_output=True, timeout=10)
    assert p.returncode == 1 and "unterminated frame" in p.stderr
    # EOF must finalize and release the lock without requiring a shutdown request.
    eof = Client(user)
    eof.init()
    eof.p.stdin.close()
    assert eof.p.wait(timeout=10) == 0
    eof.cleanup()
    after_eof = Client(user)
    after_eof.init()
    after_eof.close()
    print("PASS: init/deploy/schema/keys/select/clear, framing, lock/EOF release, restart and private errors")
    print(json.dumps(dict(info=info, deploy_ms=deploy_ms, peak_rss=peak_rss, key_ms_max=max(timings), key_ms_mean=sum(timings)/len(timings))))
