
function handleAppRequest(r) {
    r.return(200, JSON.stringify({ message: "App endpoint working" }));
}
