export async function healthCheck(r) {
  try {
    const status = {
      status: 'ok',
      timestamp: new Date().toISOString()
    };

    r.return(200, JSON.stringify(status));
  } catch (e) {
    r.error(`Health check error: ${e}`);
    r.return(500, JSON.stringify({ error: 'Health check failed' }));
  }
}
