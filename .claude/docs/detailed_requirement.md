Build a production-ready **mobile-first grocery wholesale management system for Nepal**.

The goal is to digitize and automate the entire wholesale business so the owner can monitor and manage the shop remotely without being physically present.

The business sells grocery/FMCG products such as rice, sugar, oil, flour, noodles, biscuits, beverages, spices, pulses, etc.

The system must be practical for a small-to-medium Nepali wholesale business: **simple UI, powerful functionality**.

## USER ROLES

Implement proper role-based access control for:

### 1. Owner/Admin

Full access to the entire system.

Can:

* Manage products and categories
* Manage inventory
* Manage purchases
* Manage sales
* Manage orders
* Manage customers
* Manage suppliers
* Manage payments
* Manage expenses
* View accounting
* View all reports
* Manage employees
* Create roles and permissions
* Change prices
* Adjust inventory
* View audit logs
* Configure business settings

### 2. Accountant

Can:

* View/create sales
* Manage customer payments
* Manage supplier payments
* Manage purchases
* Manage customers
* Manage suppliers
* Manage expenses
* Manage invoices
* View accounting
* View financial reports

Cannot by default:

* Manage employees
* Change permissions
* Change critical settings
* Permanently delete financial records
* Change product prices

### 3. Shop Employee

Can:

* View products
* View stock
* Create sales
* Process customer orders
* Confirm orders
* Prepare orders
* Update order status
* Receive stock
* Record collected payments
* View customers
* View daily sales

Cannot by default:

* View profit/loss
* Access complete accounting
* Change prices
* Delete transactions
* Manage employees
* Change permissions

### 4. Wholesale Customer

Can:

* Browse products
* Search/filter products
* View their applicable prices
* Add products to cart
* Place orders
* Choose delivery/pickup
* Track orders
* View invoices
* View order history
* Repeat previous orders
* View outstanding balance
* View payment history

Customers must only see their own data.

---

# CORE MODULES

Implement the following modules.

## 1. Authentication

Support:

* Login
* Logout
* Password reset
* Role-based access
* Session management
* User profile
* Phone number as a primary identifier where appropriate

After login, route the user to the correct role-specific dashboard.

---

## 2. Dashboard

### Owner Dashboard

Show:

* Today's sales
* Today's purchases
* Today's profit
* Pending orders
* Current stock
* Low-stock products
* Money receivable
* Money payable
* Customer outstanding balance
* Supplier outstanding balance
* Expenses
* Recent activity
* Employee activity

### Accountant Dashboard

Focus on:

* Sales
* Payments received
* Customer receivables
* Supplier payables
* Expenses
* Recent transactions

### Employee Dashboard

Focus on:

* Pending orders
* Today's orders
* Today's sales
* Tasks
* Low-stock alerts

### Customer Dashboard

Focus on:

* Products
* Categories
* Recent orders
* Repeat orders
* Outstanding balance
* Promotions

---

# 3. PRODUCT MANAGEMENT

Products must support:

* Product name
* SKU/code
* Category
* Brand
* Unit
* Purchase price
* Wholesale selling price
* Optional retail price
* Minimum stock level
* Current stock
* Product image
* Active/inactive status
* Description

Supported units:

* Piece
* Packet
* Box
* Carton
* Sack
* Bottle
* Dozen
* Custom unit

Support product variants where required.

Examples:

* Rice 25kg sack
* Rice 50kg sack
* Cooking Oil 1L
* Cooking Oil 5L
* Noodles carton

---

# 4. INVENTORY

Inventory must be automatically updated.

### Purchase

Purchase received → stock increases.

### Sale

Sale completed → stock decreases.

### Customer Order

Order confirmed → stock is reserved.

Order cancelled → reserved stock is released.

Order delivered/completed → stock is finalized.

### Return

Product returned → stock and accounting are updated.

### Adjustment

Admin can manually adjust stock with a required reason.

Track:

* Stock in
* Stock out
* Adjustments
* Returns
* Damaged products
* Expired products
* Current stock
* Reserved stock
* Available stock

Every inventory change must create an audit record.

---

# 5. SALES

Implement:

* Create sale
* Select customer
* Add products
* Quantity
* Price
* Discount
* Total
* Paid amount
* Remaining amount
* Payment method
* Credit sale
* Invoice
* Sales history
* Sales return
* Cancel sale

Payment methods:

* Cash
* Bank
* Digital payment
* Credit

---

# 6. CUSTOMER ORDERS

Order lifecycle:

`PLACED → CONFIRMED → PREPARING → READY / OUT_FOR_DELIVERY → DELIVERED`

Also support:

`CANCELLED`

Order should contain:

* Customer
* Products
* Quantities
* Prices
* Discount
* Total
* Payment status
* Delivery/pickup
* Address
* Notes
* Order status
* Created date
* Updated date

Customers should receive notifications when order status changes.

Employees should receive notifications for new orders.

---

# 7. PURCHASING

Implement:

* Supplier management
* Purchase order
* Create purchase
* Receive stock
* Purchase invoice
* Purchase return
* Supplier payment
* Outstanding supplier balance
* Purchase history

Purchase should automatically update inventory and supplier payable.

---

# 8. CUSTOMER MANAGEMENT

Store:

* Customer name
* Shop/business name
* Phone
* Address
* Credit limit
* Current balance
* Purchase history
* Order history
* Payment history
* Invoices
* Customer-specific pricing/discount

Important:

A credit sale increases the customer's outstanding balance.

A payment decreases the outstanding balance.

Prevent sales that exceed the customer's credit limit unless the authorized user approves it.

---

# 9. SUPPLIER MANAGEMENT

Store:

* Supplier name
* Business name
* Phone
* Address
* Products supplied
* Purchase history
* Amount payable
* Payment history
* Invoices

Purchase on credit increases supplier payable.

Supplier payment decreases supplier payable.

---

# 10. ACCOUNTING

Implement basic business accounting rather than attempting to build a complex enterprise accounting system.

Track:

* Customer receivables
* Supplier payables
* Sales
* Purchases
* Payments received
* Payments made
* Expenses
* Cash transactions
* Bank transactions
* Digital payments
* Credit transactions
* Profit/loss

Every financial transaction should be traceable to its source.

---

# 11. EXPENSES

Track:

* Expense category
* Description
* Amount
* Date
* Payment method
* Notes
* Created by

Examples:

* Rent
* Electricity
* Transport
* Salary
* Maintenance
* Miscellaneous

---

# 12. INVOICES

Automatically generate invoices for sales/orders.

Invoice should contain:

* Business information
* Invoice number
* Date
* Customer
* Products
* Quantities
* Unit prices
* Discount
* Total
* Paid amount
* Remaining amount
* Payment status

Customers should be able to view their invoices.

---

# 13. PAYMENTS

Implement a unified payment system.

Track:

* Customer payments
* Supplier payments
* Expenses
* Payment method
* Amount
* Date
* Reference
* Notes
* Created by

Maintain complete payment history.

---

# 14. REPORTS

Owner and authorized users should have:

* Daily sales
* Weekly sales
* Monthly sales
* Sales by product
* Sales by customer
* Purchase reports
* Expense reports
* Profit/loss
* Inventory report
* Stock movement
* Customer outstanding
* Supplier outstanding
* Payment report
* Best-selling products
* Employee performance

Reports should support:

* Date range
* Search
* Filters
* Export where appropriate

---

# 15. EMPLOYEE MANAGEMENT

Owner can:

* Add employee
* Edit employee
* Activate/deactivate employee
* Assign role
* Assign custom permissions
* View employee activity

Track:

* Login/activity
* Sales created
* Orders processed
* Stock changes
* Payments recorded
* Other important actions

---

# 16. CUSTOM PERMISSIONS

Implement permission-based authorization, not only hardcoded roles.

Permissions should include:

* view_sales
* create_sales
* edit_sales
* cancel_sales
* view_purchases
* create_purchases
* manage_inventory
* adjust_inventory
* view_customers
* manage_customers
* view_suppliers
* manage_suppliers
* record_payments
* manage_expenses
* view_accounting
* view_reports
* manage_products
* change_prices
* manage_employees
* manage_permissions
* manage_settings

Owner can create custom roles by combining permissions.

The frontend must hide inaccessible screens/actions.

The backend must also enforce permissions. Never rely only on frontend restrictions.

---

# 17. AUDIT LOG

Create an immutable activity/audit log for important actions.

Track:

* User
* Action
* Entity
* Entity ID
* Previous value where appropriate
* New value where appropriate
* Timestamp

Examples:

* Product price changed
* Stock adjusted
* Sale cancelled
* Payment recorded
* Customer balance changed
* Order cancelled
* Employee permission changed

Owner can view audit history.

---

# 18. NOTIFICATIONS

Implement role-based notifications.

Examples:

* New customer order
* Order confirmed
* Order delivered
* Low stock
* Payment received
* Customer payment overdue
* Supplier payment due
* Purchase received
* Stock adjustment
* Important admin activity

---

# 19. DELIVERY

Support:

* Customer pickup
* Shop delivery

Store:

* Delivery address
* Contact number
* Delivery status
* Delivery notes
* Assigned employee if needed

---

# 20. BUSINESS SETTINGS

Owner can configure:

* Business name
* Logo
* Address
* Phone
* Invoice settings
* Tax settings if required
* Currency
* Payment methods
* Order settings
* Notification settings
* Low-stock threshold defaults

Use **Rs. / NPR** as the default currency.

---

# 21. AUTOMATION RULES

The system should automatically maintain business state.

Examples:

Purchase received:
`Purchase → Inventory ↑ → Supplier payable ↑`

Customer sale on credit:
`Sale → Inventory ↓ → Customer receivable ↑`

Customer payment:
`Payment → Customer receivable ↓`

Supplier payment:
`Payment → Supplier payable ↓`

Expense:
`Expense → Cash/Bank ↓ → Expense ↑`

Customer order:
`Order → Stock reservation`

Order cancellation:
`Order cancelled → Stock reservation released`

Order completion:
`Order completed → Final stock deduction`

Low stock:
`Stock below threshold → Notification`

Every automatic change must be traceable.

---

# 22. UI / UX

Build a modern **mobile-first application**.

The design should be:

* Simple
* Fast
* Professional
* Familiar
* Easy for Nepali shop workers
* Suitable for daily use

Do NOT make it look like a complicated ERP.

Use:

* Clear dashboards
* Large readable numbers
* Cards
* Lists
* Search
* Filters
* Status badges
* Bottom navigation
* Simple forms
* Minimal steps
* Confirmation dialogs
* Notifications
* Empty states
* Loading states
* Error states

Use familiar labels:

`Sales`
`Purchase`
`Stock`
`Orders`
`Customers`
`Suppliers`
`Payments`
`Expenses`
`Reports`

Avoid unnecessary technical terminology.

---

# 23. MOBILE NAVIGATION

Navigation should change based on role.

### Owner

Dashboard
Inventory
Orders
Sales
More

Inside More:

Purchases
Customers
Suppliers
Payments
Expenses
Accounting
Reports
Employees
Settings

### Accountant

Dashboard
Sales
Orders
Payments
More

### Employee

Home
Orders
Sales
Stock
Customers

### Customer

Home
Products
Cart
Orders
Account

---

# 24. IMPORTANT BUSINESS RULES

Implement proper validation.

Examples:

* Cannot sell more available stock than allowed.
* Cannot create invalid quantities.
* Cannot record a payment greater than the outstanding amount unless explicitly allowed.
* Cannot exceed customer credit limit without authorization.
* Cannot modify completed financial transactions without proper permission.
* Stock adjustments require a reason.
* Cancelled transactions should remain in history.
* Important records should not be permanently deleted.
* Price changes should be audited.
* Permission changes should be audited.

Use soft deletion where appropriate.

---

# 25. ARCHITECTURE

Build the application with a clean, maintainable architecture.

Separate:

* UI
* State management
* Business logic
* Data layer
* API layer
* Authentication
* Authorization

Create reusable components and services.

Do not duplicate business logic across screens.

Keep business rules centralized.

Design the backend/data model so the system can scale beyond one shop if needed.

---

# 26. DEVELOPMENT APPROACH

Do NOT try to implement everything randomly.

Build in phases:

### Phase 1

Authentication + roles + navigation + base UI

### Phase 2

Products + categories + inventory

### Phase 3

Purchases + suppliers

### Phase 4

Sales + customers

### Phase 5

Customer ordering

### Phase 6

Payments + accounting + expenses

### Phase 7

Reports + dashboards

### Phase 8

Notifications + audit logs

### Phase 9

Role permissions + security hardening

### Phase 10

Testing + performance + production readiness

Before implementing a feature, understand its effect on inventory, accounting, permissions and audit history.

Do not create isolated CRUD screens that don't integrate with the rest of the business.

The final product should behave as **one connected system**.

---

# PRIMARY GOAL

The final application should allow the owner to run the wholesale business remotely.

The owner should be able to open the app and immediately know:

* How much was sold today?
* How much stock is available?
* What products are running low?
* How many orders are pending?
* Who owes the business money?
* Who does the business owe money to?
* How much was spent?
* What is the current profit?
* What are employees doing?
* What happened in the business today?

Build the system around this goal.

Do not overcomplicate the UI, but do not remove important business functionality.
