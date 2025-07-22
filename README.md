is_shared.js (Base functionality)
├── SharedChatBase (Common chat features)
├── SharedInterface (Auth, navigation, alerts)
└── SharedModalUtils (Modal helpers)

is_guest.js (Extends SharedChatBase)
├── GuestChat → localStorage, 10 message limit
└── GuestChallengeResponder → Handle incoming challenges

is_approved.js (Extends SharedChatBase)  
├── ApprovedChat → Redis storage, unlimited messages
└── History loading, export functions

is_admin.js (Extends ApprovedChat)
├── AdminChat → All approved features + admin UI
└── User management, system monitoring functions

is_none.js (Independent - guest session creation)
├── GuestSessionManager → Create guest sessions
└── GuestStatsDisplay → Show availability