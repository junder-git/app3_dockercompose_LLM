// init.js - Application Initialization and Setup

class AppInit {
    constructor() {
        this.initialized = false;
        this.adminUser = null;
        
        // Configuration
        this.config = {
            ADMIN_USERNAME: 'admin',
            ADMIN_PASSWORD: 'admin',
            ADMIN_USER_ID: 'admin',
            USER_ID_COUNTER_START: 1000
        };
        
        console.log('⚙️ AppInit created');
    }

    async runStartup() {
        try {
            console.log('🚀 Running application startup...');
            
            // Initialize database
            if (!window.Database.initialized) {
                await window.Database.init();
            }
            
            // Run database migrations
            await this.runMigrations();
            
            // Initialize user ID counter
            await this.initializeUserIdCounter();
            
            // Create admin user if needed
            await this.createAdminUser();
            
            // Cleanup expired data
            await this.cleanupExpiredData();
            
            // Validate data integrity
            await this.validateSystemIntegrity();
            
            this.initialized = true;
            console.log('✅ Application startup complete');
            
        } catch (error) {
            console.error('❌ Startup failed:', error);
            throw error;
        }
    }

    async runMigrations() {
        try {
            console.log('🔄 Running database migrations...');
            
            // Check migration status
            const migrationResult = await window.Database.migrateLegacyData();
            
            if (migrationResult.success) {
                console.log('✅ Migrations complete:', migrationResult.message);
            } else {
                throw new Error('Migration failed: ' + migrationResult.message);
            }
            
        } catch (error) {
            console.error('❌ Migration error:', error);
            throw error;
        }
    }

    async initializeUserIdCounter() {
        try {
            // Check if counter exists
            const counterExists = await window.Database.exists('user_id_counter');
            
            if (!counterExists) {
                console.log('🔢 Initializing user ID counter...');
                
                // Set initial counter value
                await window.Database.set('user_id_counter', this.config.USER_ID_COUNTER_START);
                console.log(`✅ User ID counter initialized to ${this.config.USER_ID_COUNTER_START}`);
            } else {
                const currentValue = await window.Database.get('user_id_counter');
                console.log(`✅ User ID counter exists: ${currentValue}`);
            }
            
        } catch (error) {
            console.error('❌ Error initializing user ID counter:', error);
            throw error;
        }
    }

    async createAdminUser() {
        try {
            console.log('👤 Checking admin user...');
            
            // Check if admin user exists
            let adminUser = await window.Database.getUserByUsername(this.config.ADMIN_USERNAME);
            
            if (!adminUser) {
                console.log('🔧 Creating admin user...');
                
                // Hash admin password
                const passwordHash = await this.hashPassword(this.config.ADMIN_PASSWORD);
                
                // Create admin user
                adminUser = new User(
                    this.config.ADMIN_USER_ID,
                    this.config.ADMIN_USERNAME,
                    passwordHash,
                    true, // is_admin
                    true  // is_approved
                );
                
                await window.Database.saveUser(adminUser);
                
                console.log('✅ Admin user created successfully');
                console.log(`📝 Username: ${this.config.ADMIN_USERNAME}`);
                console.log(`📝 Password: ${this.config.ADMIN_PASSWORD}`);
                console.log('⚠️ Please change the admin password after first login!');
                
            } else {
                console.log('✅ Admin user exists:', adminUser.username);
                
                // Ensure admin user has correct privileges
                if (!adminUser.is_admin || !adminUser.is_approved) {
                    console.log('🔧 Updating admin user privileges...');
                    adminUser.is_admin = true;
                    adminUser.is_approved = true;
                    await window.Database.saveUser(adminUser);
                    console.log('✅ Admin privileges updated');
                }
            }
            
            this.adminUser = adminUser;
            
        } catch (error) {
            console.error('❌ Error creating admin user:', error);
            throw error;
        }
    }

    async cleanupExpiredData() {
        try {
            console.log('🧹 Cleaning up expired data...');
            
            // Cleanup expired sessions
            const sessionResult = await window.Database.cleanupExpiredSessions();
            if (sessionResult.success && sessionResult.cleaned_sessions > 0) {
                console.log(`✅ Cleaned ${sessionResult.cleaned_sessions} expired sessions`);
            }
            
            // Could add more cleanup operations here
            // - Old cached responses
            // - Expired rate limit entries
            // - Orphaned message data
            
        } catch (error) {
            console.warn('⚠️ Cleanup error (non-critical):', error);
            // Don't throw - cleanup errors shouldn't stop startup
        }
    }

    async validateSystemIntegrity() {
        try {
            console.log('🔍 Validating system integrity...');
            
            const integrityResult = await window.Database.validateDataIntegrity();
            
            if (integrityResult.success) {
                if (integrityResult.issues_found > 0) {
                    console.warn(`⚠️ Found ${integrityResult.issues_found} data integrity issues:`, integrityResult.issues);
                } else {
                    console.log('✅ Data integrity check passed');
                }
            }
            
        } catch (error) {
            console.warn('⚠️ Integrity check error (non-critical):', error);
            // Don't throw - integrity errors shouldn't stop startup
        }
    }

    // =====================================================
    // PASSWORD HASHING UTILITIES
    // =====================================================

    async hashPassword(password) {
        try {
            // In a browser environment, we'll use a simple but secure method
            // For production, consider using a more robust hashing library
            
            const encoder = new TextEncoder();
            const data = encoder.encode(password + 'devstral_salt_2024');
            const hashBuffer = await crypto.subtle.digest('SHA-256', data);
            const hashArray = Array.from(new Uint8Array(hashBuffer));
            const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
            
            return hashHex;
        } catch (error) {
            console.error('❌ Password hashing error:', error);
            throw new Error('Failed to hash password');
        }
    }

    async verifyPassword(password, hash) {
        try {
            const computedHash = await this.hashPassword(password);
            return computedHash === hash;
        } catch (error) {
            console.error('❌ Password verification error:', error);
            return false;
        }
    }

    // =====================================================
    // SYSTEM INFORMATION
    // =====================================================

    async getSystemInfo() {
        try {
            const stats = await window.Database.getDatabaseStats();
            const health = await window.Database.getSystemHealth();
            
            return {
                app_version: '1.0.0',
                database_stats: stats,
                system_health: health,
                admin_user: this.adminUser ? {
                    id: this.adminUser.id,
                    username: this.adminUser.username,
                    created_at: this.adminUser.created_at
                } : null,
                initialized: this.initialized,
                startup_time: new Date().toISOString()
            };
        } catch (error) {
            console.error('❌ Error getting system info:', error);
            throw error;
        }
    }

    async resetSystem(confirmationText) {
        if (confirmationText !== 'RESET_ALL_DATA') {
            throw new Error('Invalid confirmation text');
        }
        
        try {
            console.log('🔥 RESETTING ENTIRE SYSTEM...');
            
            // Clear all database data
            await window.Database.flushdb();
            
            // Re-run initialization
            this.initialized = false;
            await this.runStartup();
            
            console.log('✅ System reset complete');
            
            return {
                success: true,
                message: 'System has been completely reset',
                timestamp: new Date().toISOString()
            };
            
        } catch (error) {
            console.error('❌ System reset failed:', error);
            throw error;
        }
    }

    // =====================================================
    // CONFIGURATION MANAGEMENT
    // =====================================================

    updateConfig(newConfig) {
        this.config = { ...this.config, ...newConfig };
        console.log('⚙️ Configuration updated:', this.config);
    }

    getConfig() {
        return { ...this.config };
    }

    // =====================================================
    // HEALTH MONITORING
    // =====================================================

    async performHealthCheck() {
        try {
            const health = {
                status: 'healthy',
                timestamp: new Date().toISOString(),
                checks: {
                    database: false,
                    admin_user: false,
                    initialization: false
                },
                details: {}
            };
            
            // Database check
            try {
                await window.Database.ping();
                health.checks.database = true;
            } catch (error) {
                health.checks.database = false;
                health.details.database_error = error.message;
                health.status = 'unhealthy';
            }
            
            // Admin user check
            if (this.adminUser) {
                health.checks.admin_user = true;
            } else {
                health.checks.admin_user = false;
                health.details.admin_user_error = 'Admin user not initialized';
                health.status = 'degraded';
            }
            
            // Initialization check
            health.checks.initialization = this.initialized;
            if (!this.initialized) {
                health.details.initialization_error = 'System not fully initialized';
                health.status = 'unhealthy';
            }
            
            return health;
        } catch (error) {
            console.error('❌ Health check error:', error);
            return {
                status: 'error',
                timestamp: new Date().toISOString(),
                error: error.message
            };
        }
    }

    // =====================================================
    // UTILITY METHODS
    // =====================================================

    generateSecureToken() {
        const array = new Uint8Array(32);
        crypto.getRandomValues(array);
        return Array.from(array, byte => byte.toString(16).padStart(2, '0')).join('');
    }

    getCurrentTimestamp() {
        return new Date().toISOString();
    }

    formatBytes(bytes) {
        if (bytes === 0) return '0 Bytes';
        const k = 1024;
        const sizes = ['Bytes', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
    }
}

// Create global instance
window.AppInit = new AppInit();

// Export for module use
if (typeof module !== 'undefined' && module.exports) {
    module.exports = AppInit;
}