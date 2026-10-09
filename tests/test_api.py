from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_home_endpoint():
    response = client.get('/')
    assert response.status_code == 200
    assert response.json()['message'] == 'Wallet Ledger API is running'

def test_health_endpoint():
    response = client.get('/health')
    assert response.status_code == 200
    assert response.json()['status'] == 'ok'
    assert response.json()['database'] == 'connected'

def test_alice_wallet_balance():
    response = client.get('/wallets/1/balance')
    assert response.status_code == 200
    data = response.json()
    assert data['wallet_id'] == 1
    assert data['currency'] == 'INR'
    assert data['balance_minor'] == 70000
    assert data['balance'] == 700.0

def test_bob_wallet_balance():
    response = client.get('/wallets/2/balance')
    assert response.status_code == 200
    data = response.json()
    assert data['wallet_id'] == 2
    assert data['currency'] == 'INR'
    assert data['balance_minor'] == 30000
    assert data['balance'] == 300.0

def test_missing_wallet():
    response = client.get('/wallets/999999/balance')
    assert response.status_code == 404
    assert response.json()['detail'] == 'Wallet not found'
