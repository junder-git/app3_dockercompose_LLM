
function healthCheck(r) {
    r.return(200, JSON.stringify({ status: "ok" }));
}
