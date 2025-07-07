
function handleAdminRequest(r) {
    r.return(200, JSON.stringify({ message: "Admin endpoint working" }));
}
