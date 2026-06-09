'use strict';

const http = require('http');
const { URL } = require('url');
const crypto = require('crypto');
const { LoginSession, EAuthTokenPlatformType } = require('steam-session');
const WebApiTransport = require('steam-session/dist/transports/WebApiTransport').default;

const HOST = process.env.LORDZ_QR_HOST || '127.0.0.1';
const PORT = Number(process.env.LORDZ_QR_PORT || 8765);
const LOG_FILE = process.env.LORDZ_QR_LOG || null;

/** @type {Map<string, { session: LoginSession, logs: string[] }>} */
const sessions = new Map();

function log(message, sessionId = '-') {
  const line = `[${new Date().toISOString()}] [${sessionId}] ${message}`;
  console.log(line);
  if (LOG_FILE) {
    require('fs').appendFileSync(LOG_FILE, line + '\n');
  }
}

function sendJson(res, statusCode, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
  });
  res.end(body);
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let raw = '';
    req.on('data', chunk => {
      raw += chunk;
      if (raw.length > 1_000_000) {
        reject(new Error('Request body too large.'));
        req.destroy();
      }
    });
    req.on('end', () => {
      if (!raw) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(raw));
      } catch (err) {
        reject(new Error('Invalid JSON body.'));
      }
    });
    req.on('error', reject);
  });
}

function getSessionRecord(sessionId) {
  const record = sessions.get(sessionId);
  if (!record) {
    return null;
  }
  return record;
}

function createSessionRecord(sessionId, kind) {
  return {
    kind,
    logs: [],
    state: 'starting',
    clientId: null,
    requestId: null,
    challengeUrl: null,
    pollInterval: 2,
    accountName: null,
    refreshToken: null,
    accessToken: null,
    lastError: null,
    validActions: []
  };
}

function attachSessionHandlers(sessionId, session, record) {
  const push = msg => {
    record.logs.push(msg);
    log(msg, sessionId);
  };

  session.on('polling', () => push('polling'));
  session.on('remoteInteraction', () => {
    if (record.state !== 'authenticated') {
      record.state = 'scanned';
    }
    push('remoteInteraction');
  });
  session.on('authenticated', () => {
    record.state = 'authenticated';
    record.accountName = session.accountName;
    record.refreshToken = session.refreshToken;
    record.accessToken = session.accessToken || null;
    push(`authenticated as ${session.accountName}`);
  });
  session.on('timeout', () => {
    record.state = 'timeout';
    push('timeout');
  });
  session.on('error', err => {
    record.state = 'error';
    record.lastError = err && err.message ? err.message : String(err);
    push(`error: ${record.lastError}`);
  });

  return push;
}

async function startCredentialSession(body) {
  const accountName = String(body.accountName || '').trim();
  const password = String(body.password || '');
  const steamGuardCode = body.steamGuardCode ? String(body.steamGuardCode).trim() : null;

  if (!accountName || !password) {
    throw new Error('accountName and password are required.');
  }

  const sessionId = crypto.randomBytes(8).toString('hex');
  const session = new LoginSession(EAuthTokenPlatformType.SteamClient, {
    transport: new WebApiTransport()
  });
  session.loginTimeout = Number(process.env.LORDZ_LOGIN_TIMEOUT_MS || 300000);

  const record = createSessionRecord(sessionId, 'credentials');
  record.session = session;
  const push = attachSessionHandlers(sessionId, session, record);
  sessions.set(sessionId, record);
  push(`starting credential login for ${accountName}`);

  try {
    const startResult = await session.startWithCredentials({
      accountName,
      password,
      steamGuardCode: steamGuardCode || undefined
    });

    record.accountName = session.accountName || accountName;
    if (startResult.actionRequired) {
      record.state = 'guard_required';
      record.validActions = (startResult.validActions || []).map(action => ({
        type: action.type,
        detail: action.detail || null
      }));
      push(`guard required: ${record.validActions.map(item => item.type).join(', ') || 'unknown'}`);
    } else {
      record.state = 'authenticating';
      push('credentials accepted, waiting for authenticated event');
    }
  } catch (err) {
    record.state = 'error';
    record.lastError = err && err.message ? err.message : String(err);
    push(`credential start failed: ${record.lastError}`);
    throw err;
  }

  return getLoginSnapshot(sessionId);
}

async function submitCredentialGuardCode(body) {
  const sessionId = String(body.sessionId || '').trim();
  const code = String(body.code || '').trim();
  const record = getSessionRecord(sessionId);

  if (!record || record.kind !== 'credentials') {
    throw new Error('Unknown credential login session.');
  }
  if (!code) {
    throw new Error('Steam Guard code is required.');
  }

  record.logs.push('submitting Steam Guard code');
  log('submitting Steam Guard code', sessionId);
  await record.session.submitSteamGuardCode(code);
  record.state = 'authenticating';
  return getLoginSnapshot(sessionId);
}

function getLoginSnapshot(sessionId) {
  const record = getSessionRecord(sessionId);
  if (!record || record.kind !== 'credentials') {
    return { success: false, message: 'Unknown credential login session id.' };
  }

  const needsCode = (record.validActions || []).some(action =>
    action.type === 2 || action.type === 3 || action.type === 'EmailCode' || action.type === 'DeviceCode'
  );
  const needsConfirmation = (record.validActions || []).some(action =>
    action.type === 4 || action.type === 5 || action.type === 'DeviceConfirmation' || action.type === 'EmailConfirmation'
  );

  return {
    success: true,
    sessionId,
    state: record.state,
    complete: record.state === 'authenticated',
    accountName: record.accountName,
    refreshToken: record.refreshToken,
    accessToken: record.accessToken,
    validActions: record.validActions,
    needsSteamGuardCode: needsCode,
    needsConfirmation,
    message: record.lastError || (
      record.state === 'authenticated'
        ? 'Credential login approved.'
        : record.state === 'guard_required'
          ? 'Steam Guard action required.'
          : record.state === 'scanned'
            ? 'Steam Guard prompt viewed. Approve on your phone.'
            : 'Waiting for Steam login...'
    ),
    logs: record.logs.slice(-30)
  };
}

async function startQrSession() {
  const sessionId = crypto.randomBytes(8).toString('hex');
  const session = new LoginSession(EAuthTokenPlatformType.MobileApp);
  session.loginTimeout = 120000;

  const record = createSessionRecord(sessionId, 'qr');
  record.session = session;
  const push = attachSessionHandlers(sessionId, session, record);

  sessions.set(sessionId, record);
  push('starting QR session');

  const startResult = await session.startWithQR();
  record.state = 'waiting';
  record.challengeUrl = startResult.qrChallengeUrl;
  record.pollInterval = Math.max(1.5, session._startSessionResponse?.pollInterval || 2);

  if (session._startSessionResponse) {
    record.clientId = String(session._startSessionResponse.clientId || '');
    const requestId = session._startSessionResponse.requestId;
    record.requestId = Buffer.isBuffer(requestId)
      ? requestId.toString('base64')
      : Buffer.from(requestId || []).toString('base64');
  }

  push(`challenge ready: ${record.challengeUrl}`);

  return {
    sessionId,
    challengeUrl: record.challengeUrl,
    pollInterval: record.pollInterval,
    clientId: record.clientId,
    requestId: record.requestId
  };
}

function getPollSnapshot(sessionId) {
  const record = getSessionRecord(sessionId);
  if (!record) {
    return { success: false, message: 'Unknown session id.' };
  }

  const session = record.session;
  const response = session._startSessionResponse || {};

  return {
    success: true,
    sessionId,
    state: record.state,
    complete: record.state === 'authenticated',
    remoteInteraction: record.state === 'scanned' || record.state === 'authenticated',
    accountName: record.accountName,
    refreshToken: record.refreshToken,
    accessToken: record.accessToken,
    newChallengeUrl: response.challengeUrl || record.challengeUrl,
    newClientId: response.clientId ? String(response.clientId) : record.clientId,
    pollInterval: record.pollInterval,
    message: record.lastError || (record.state === 'authenticated' ? 'QR login approved.' : 'Waiting for approval...'),
    logs: record.logs.slice(-20)
  };
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') {
    sendJson(res, 204, {});
    return;
  }

  const url = new URL(req.url, `http://${HOST}:${PORT}`);

  try {
    if (req.method === 'GET' && url.pathname === '/health') {
      sendJson(res, 200, {
        ok: true,
        service: 'lordz-steam-qr-server',
        sessions: sessions.size
      });
      return;
    }

    if (req.method === 'POST' && url.pathname === '/api/qr/start') {
      const payload = await startQrSession();
      sendJson(res, 200, { success: true, ...payload });
      return;
    }

    if (req.method === 'GET' && url.pathname.startsWith('/api/qr/poll/')) {
      const sessionId = decodeURIComponent(url.pathname.replace('/api/qr/poll/', ''));
      const snapshot = getPollSnapshot(sessionId);
      const status = snapshot.success ? 200 : 404;
      sendJson(res, status, snapshot);
      return;
    }

    if (req.method === 'GET' && url.pathname === '/api/qr/logs') {
      const sessionId = url.searchParams.get('sessionId');
      const record = sessionId ? getSessionRecord(sessionId) : null;
      sendJson(res, 200, {
        success: true,
        sessionId,
        logs: record ? record.logs : []
      });
      return;
    }

    if (req.method === 'POST' && url.pathname === '/api/login/start') {
      const body = await readJson(req);
      const snapshot = await startCredentialSession(body);
      sendJson(res, 200, snapshot);
      return;
    }

    if (req.method === 'GET' && url.pathname.startsWith('/api/login/poll/')) {
      const sessionId = decodeURIComponent(url.pathname.replace('/api/login/poll/', ''));
      const snapshot = getLoginSnapshot(sessionId);
      const status = snapshot.success ? 200 : 404;
      sendJson(res, status, snapshot);
      return;
    }

    if (req.method === 'POST' && url.pathname === '/api/login/guard') {
      const body = await readJson(req);
      const snapshot = await submitCredentialGuardCode(body);
      sendJson(res, 200, snapshot);
      return;
    }

    sendJson(res, 404, { success: false, message: 'Not found.' });
  } catch (err) {
    log(`request failed: ${err.message}`);
    sendJson(res, 500, { success: false, message: err.message || String(err) });
  }
});

server.listen(PORT, HOST, () => {
  log(`LordZ Steam QR backend listening on http://${HOST}:${PORT}`);
});
