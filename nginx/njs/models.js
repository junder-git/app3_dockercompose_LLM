function User(data) {
    data = data || {};
    this.id = data.id || "";
    this.username = data.username || "";
    this.password_hash = data.password_hash || "";
    this.is_admin = data.is_admin || false;
    this.is_approved = data.is_approved || false;
    this.created_at = data.created_at || "";
}

User.prototype.toDict = function () {
    return {
        id: this.id,
        username: this.username,
        password_hash: this.password_hash,
        is_admin: this.is_admin,
        is_approved: this.is_approved,
        created_at: this.created_at
    };
};

export default { User };