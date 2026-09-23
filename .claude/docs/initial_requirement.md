Act as a Senior Mobile App UI/UX Designer and Lead Frontend Developer specializing in intuitive business apps for emerging markets. 

Build a standalone, frontend-only mobile application tailored for a two-person wholesale grocery and FMCG business in Nepal. The UI must be clean, minimal, non-corporate, and optimized for fast daily mobile entry by non-tech-savvy users.

### Technical Scope & Architecture
- Framework: Flutter or React Native (Mobile-first UI).
- Backend: None (Frontend UI with local state management and local storage like SQLite/Hive/AsyncStorage using mock data).
- Currency & Formatting: Nepali Rupee (NPR, e.g., NPR 2,50,000) with standard local date formats.
- Design Aesthetic: Simple, high-contrast, large tap targets, card-based navigation, zero fluff.

---

### Core App Structure & Modules

#### 1. Quick Dashboard
- High-level metric cards: Today's Sales, Cash in Hand, Outstanding Customer Credit, Low Stock Count.
- Role Quick Switch / View Toggle:
  - Finance & Admin View (Focus on Cash, Margins, Credit Limits, Reports).
  - Sales & Operations View (Focus on Inventory, Quick Order Entry, Customer Visit/Collection).

#### 2. Inventory Management
- Product Catalog: FMCG categories (Rice, Oil, Sugar, Spices, Beverages, etc.).
- Stock Tracking: Physical vs. Recorded stock count input, unit prices, and supplier invoice tagging.
- Stock Adjustments: Quick log for Damaged Goods, Expired Items, or Supplier Returns.
- Visual Badges: Red tag for "Low Stock" and Yellow tag for "Near Expiry".

#### 3. Sales & Order Entry
- Quick Order Pad: Select customer, pick items, set quantity, apply approved percentage/flat discount.
- Sales Approval Guardrail: Auto-flag or require joint approval if order discount exceeds normal margin limits or customer exceeds credit limit.
- Receipt Generation: Simple digital invoice preview ready for local printing or WhatsApp sharing.

#### 4. Customer & Credit Control
- Customer Directory: Name, Phone, Location, Assigned Credit Limit, and Current Outstanding Balance.
- Credit Status Indicators:
  - Green: Safe (Within limit & timeframe).
  - Yellow: Payment Due Soon.
  - Red: Overdue / Limit Exceeded (Block new credit sales until resolved).
- Payment Collection Log: Simple form to record cash/cheque received against specific customer balances.

#### 5. Cash & Finance Management
- Daily Cash Ledger: Log opening cash, cash sales, field collections, cash expenses (rent, transport, packaging), and bank deposits.
- Expense Logger: Category breakdown (Rent, Transport, Utilities, Tea/Misc) with receipt photo placeholder.
- Partner Loan & Capital Ledger: Dedicated tab tracking partner loan balances, repayments, and agreed profit distribution milestones.

---

### Key UX Requirements
1. Single-Tap Actions: Floating action buttons (+ New Sale, + Add Expense, + Collect Payment) visible on the home screen.
2. Offline-First Feel: Fast, local-state updates without loading spinners.
3. Plain Language: Use plain business terms ("Money In", "Money Out", "Udharo / Credit", "Stock Balance") instead of complex corporate jargon.