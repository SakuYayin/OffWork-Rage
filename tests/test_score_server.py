"""Real HTTP + SQLite regression; no external dependencies or production data."""
import concurrent.futures
from contextlib import closing
import http.client
import json
from pathlib import Path
import sqlite3
import tempfile
import threading
import unittest
import uuid
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import server

class ScoreApi(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / "index.html").write_text("<html><head></head><body>game</body></html>")
        (self.root / "server.py").write_text("private")
        self.start()

    def start(self):
        self.http = server.make_server("127.0.0.1", 0, self.root, self.root / "data")
        self.thread = threading.Thread(target=self.http.serve_forever, daemon=True)
        self.thread.start()

    def stop(self):
        self.http.shutdown(); self.http.server_close(); self.thread.join()

    def tearDown(self):
        self.stop(); self.temp.cleanup()

    def request(self, method, route="/api/leaderboard", payload=None, raw=None, headers=None):
        con = http.client.HTTPConnection("127.0.0.1", self.http.server_port, timeout=5)
        data = raw if raw is not None else json.dumps(payload, ensure_ascii=False).encode("utf8") if payload is not None else None
        con.request(method, route, data, headers or ({"Content-Type": "application/json"} if data else {}))
        response = con.getresponse(); body = response.read(); status = response.status; con.close()
        try: return status, json.loads(body)
        except ValueError: return status, body.decode()

    def entry(self, **overrides):
        e = dict(name='实习生 "许宁" | ; % 😀 abc123', wave=6, boss=2, level=4, kills=50, time=125,
                 mode="endless", hero="intern", version=server.VERSION, ruleset=server.RULESET, run_id=str(uuid.uuid4()))
        e.update(overrides)
        e.setdefault("score", 1000*e["wave"]+1500*e["boss"]+12*e["kills"]+40*e["level"]+3*min(3600,e["time"]))
        return e

    def test_fufu_scores_are_accepted(self):
        for mode in ("campaign", "endless"):
            entry = self.entry(hero="fufu", mode=mode, name="符符与小动物")
            status, data = self.request("POST", payload=entry)
            self.assertEqual(status, 200)
            self.assertEqual(data["entries"][0]["hero"], "fufu")

    def test_unicode_idempotency_modes_persistence(self):
        e=self.entry()
        status,data=self.request("POST",payload=e)
        self.assertEqual(status,200);self.assertEqual(data["rank"],1);self.assertFalse(data["repeated"])
        self.assertEqual(data["entries"][0]["name"],e["name"])
        self.assertIn("%7C",data["wire"]);self.assertIn("%3B",data["wire"])
        status,data=self.request("POST",payload=e)
        self.assertEqual(status,200);self.assertTrue(data["repeated"])
        self.assertEqual(self.request("POST",payload={**e,"name":"different"})[0],409)
        c=self.entry(mode="campaign",boss=3,wave=2)
        self.assertEqual(self.request("POST",payload=c)[0],200)
        self.assertEqual(len(self.request("GET")[1]["entries"]),1)
        self.assertEqual(len(self.request("GET","/api/leaderboard?mode=campaign")[1]["entries"]),1)
        self.stop(); self.start()
        self.assertEqual(self.request("GET")[1]["entries"][0]["run_id"],e["run_id"])
        with closing(sqlite3.connect(self.root/"data"/"scores.sqlite3")) as con:
            self.assertEqual(con.execute("SELECT COUNT(*) FROM runs").fetchone()[0],2)
        self.assertFalse(self.request("GET","/api/config")[1]["authoritativeCombat"])

    def test_validation_and_version_isolation(self):
        for override in ({"name":" "},{"name":"A\nB"},{"score":True},{"wave":-1},{"score":999999},{"run_id":"bad"},{"hero":"bad"},{"time":86401}):
            self.assertEqual(self.request("POST",payload=self.entry(**override))[0],400,override)
        self.assertEqual(self.request("POST",payload=self.entry(ruleset="old"))[0],409)
        self.assertEqual(self.request("GET","/api/leaderboard?ruleset=old")[0],409)
        self.assertEqual(self.request("GET","/api/leaderboard?mode=bad")[0],400)
        self.assertEqual(self.request("POST",raw=b'{"name":NaN}')[0],400)
        self.assertEqual(self.request("POST",raw=b"[")[0],400)
        self.assertEqual(self.request("POST",raw=b"{}",headers={"Content-Type":"text/plain"})[0],415)
        self.assertEqual(self.request("POST",raw=b"x"*(server.MAX_BODY+1))[0],413)
        long=self.entry(name="名字"*100,hero="fufu")
        self.assertEqual(self.request("POST",payload=long)[0],200)
        self.assertEqual(len(self.request("GET")[1]["entries"]),1)

    def test_concurrent_duplicate_and_rate_limit(self):
        e=self.entry()
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            responses=list(pool.map(lambda _:self.request("POST",payload=e),range(8)))
        self.assertTrue(all(status==200 for status,_ in responses))
        self.assertEqual(sum(not data["repeated"] for _,data in responses),1)
        self.assertEqual(len(self.request("GET")[1]["entries"]),1)
        for _ in range(53): result=self.request("POST",payload=e)
        self.assertEqual(result[0],429)
        self.assertEqual(len(self.request("GET")[1]["entries"]),1)

    def test_static_privacy_and_api_flag(self):
        status,html=self.request("GET","/")
        self.assertEqual(status,200);self.assertIn("OFFWORK_API_ENABLED=true",html)
        for route in ("/server.py","/Dockerfile","/data/scores.sqlite3","/../server.py","/%2e%2e/server.py","/assets/../../server.py"):
            self.assertEqual(self.request("GET",route)[0],404,route)
        self.assertEqual(self.request("GET","/api/health")[0],200)

if __name__=="__main__":unittest.main(verbosity=2)
