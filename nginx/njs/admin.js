import database from "./database.js";

async function handleApproveUser(r) {
    var user_id = r.args.user_id;
    if (!user_id) {
        r.return(400, JSON.stringify({ error: "User ID is required" }));
        return;
    }

    var success = await database.approveUser(user_id);
    if (!success) {
        r.return(404, JSON.stringify({ error: "User not found" }));
        return;
    }

    r.return(200, JSON.stringify({ message: "User approved" }));
}

async function handleRejectUser(r) {
    var user_id = r.args.user_id;
    if (!user_id) {
        r.return(400, JSON.stringify({ error: "User ID is required" }));
        return;
    }

    var success = await database.rejectUser(user_id);
    if (!success) {
        r.return(404, JSON.stringify({ error: "User not found" }));
        return;
    }

    r.return(200, JSON.stringify({ message: "User rejected and deleted" }));
}

export default { handleApproveUser, handleRejectUser };
