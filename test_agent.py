from fastapi.testclient import TestClient
import xray_agent as agent


def test_agent_persists_add_remove_and_restore(tmp_path, monkeypatch):
    token = "A" * 64
    state_file = tmp_path / "inbounds.json"
    live_tags = set()
    commands = []
    inbound = {
        "tag": "rix-0123456789abcdef01234567",
        "listen": "0.0.0.0",
        "port": 20000,
        "protocol": "vless",
        "settings": {"clients": [{"id": "00000000-0000-4000-8000-000000000001"}], "decryption": "none"},
    }
    monkeypatch.setattr(agent, "AGENT_TOKEN", token)
    monkeypatch.setattr(agent, "STATE_PATH", state_file)
    monkeypatch.setattr(agent, "STATE", {})
    monkeypatch.setattr(agent, "PORT_START", 20000)
    monkeypatch.setattr(agent, "PORT_END", 20100)
    monkeypatch.setattr(agent, "_active_tags", lambda: set(live_tags))

    def fake_run(args, config=None):
        commands.append((args, config))
        if args[0] == "adi" and config:
            live_tags.add(config["inbounds"][0]["tag"])
        elif args[0] == "rmi":
            live_tags.discard(args[-1])
        return "{}"

    monkeypatch.setattr(agent, "_run", fake_run)
    with TestClient(agent.app) as client:
        headers = {"Authorization": f"Bearer {token}"}
        response = client.post("/v1/inbounds", json={"inbound": inbound}, headers=headers)
        assert response.status_code == 200
        tag = inbound["tag"]
        assert tag in live_tags
        assert state_file.exists()

        # Retry after a request timeout should be idempotent.
        response = client.post("/v1/inbounds", json={"inbound": inbound}, headers=headers)
        assert response.status_code == 200
        assert response.json()["already_active"] is True

        # Simulate Xray restart: API state is empty, Agent restores saved inbound.
        live_tags.clear()
        agent._reconcile_once()
        assert tag in live_tags

        response = client.delete(f"/v1/inbounds/{tag}", headers=headers)
        assert response.status_code == 200
        assert tag not in live_tags
        assert tag not in agent.STATE
        assert agent._load_state() == {}


def test_agent_rejects_unauthorized_request(monkeypatch):
    monkeypatch.setattr(agent, "AGENT_TOKEN", "B" * 64)
    with TestClient(agent.app) as client:
        r = client.get("/v1/status", headers={"Authorization": "Bearer " + "C" * 64})
        assert r.status_code == 401
