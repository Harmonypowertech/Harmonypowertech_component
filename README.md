# HPT Component Hub

## Production deployment

The application uses a shared hosted database, so employees see the same users,
components, quantities, and cupboard locations in every browser. Login sessions
are intentionally browser-specific; each browser must sign in separately.

For a GitHub-to-Vercel deployment, follow [VERCEL_DEPLOYMENT.md](./VERCEL_DEPLOYMENT.md).
The server environment variables in that guide are mandatory—frontend-only
variables cannot authenticate users or access the shared inventory securely.

Harmony Powertech (HPT) Component Management Web App

Build a professional, production-quality web application for Harmony Powertech (HPT) to manage and search electronic components.

The application must feel like a real internal business software product used by an electronics/hardware company. The UI should be modern, clean, fast, professional, responsive, and easy for employees to use.

1. BRANDING

Use the uploaded Harmony Powertech logo as the primary company logo throughout the application.

Requirements:

Use the uploaded logo asset exactly as the brand reference.

Display the logo in a high-quality, sharp/upscaled form without changing its design.

Preserve the original blue branding and typography of the logo.

Use the logo on:

Login page

Main application header

Admin login page

Admin dashboard

Sidebar/header wherever appropriate

Do not redesign or distort the logo.

Recommended professional color system

Build the website around the existing logo colors:

Primary Navy Blue: #063B6D

Deep Blue: #052A4F

Accent Blue: #1478B8

Light Blue: #EAF4FB

White: #FFFFFF

Background: #F5F7FA

Text: #17212B

Secondary Text: #667085

Border: #D9E2EC

Success: #198754

Warning: #F59E0B

Danger: #DC3545

The final combination should look like a professional industrial electronics / engineering company portal, not a generic template.

2. APPLICATION PURPOSE

The main purpose of this application is:

Employees should be able to log in, search for electronic components, view their details, and add new components.

The component database should contain:

Component Name

Part Number

Quantity

Cupboard Number

The system must only display components that actually exist in the application's database.

3. AUTHENTICATION SYSTEM

Create a secure user authentication system.

User Login

Every employee/user must have:

User Name

User ID

Password

The login page should contain:

Harmony Powertech logo

"Harmony Powertech" branding

User ID field

Password field

Login button

Show/hide password option

Error message for invalid credentials

Loading state while authenticating

Users must only be allowed into the system when their credentials exist in the registered-user database.

Do NOT allow fake/demo credentials to bypass authentication.

After successful login:

Redirect the user to the main Component Search Dashboard.

4. MAIN USER DASHBOARD

After login, create a professional dashboard.

The main focus of the screen should be a large component search interface.

Header

Header should contain:

Harmony Powertech logo

"Component Management System"

Logged-in user's name

User ID

Logout button

Main Search Area

Display a large search bar with placeholder:

"Search component name..."

Also include a search icon.

The system should allow users to search components by:

Component Name

Part Number

Search should be fast and dynamic.

As the user types, show matching results.

5. SEARCH RESULTS

After searching, show component results in a professional table/card layout.

Each result must clearly display:

Component NamePart NumberQuantityCupboard No.

Example:

Component Name: Resistor 10K
Part Number: R-10K-0805
Quantity: 250
Cupboard No.: C-03

Make the result layout highly readable.

For desktop:

Use a clean professional table.

For mobile:

Convert the result into responsive cards or a horizontal-scroll table.

Show:

Search result count

"No components found" state when there are no matches

Loading indicator while searching

Do not show fabricated components.

Only return records from the database.

6. ADD COMPONENT

Place a clearly visible button near the search bar:

+ Add Component

When the user clicks this button, open a professional modal or dedicated form page.

Add Component Form

The form must contain exactly these three user-entered fields:

Field 1

Component Name

Example:
10K Resistor

Field 2

Part Number

Example:
RC0805-10K

Field 3

Quantity

Example:
250

The form must also have a field for:

Cupboard Number

Example:
C-03

Therefore the stored component record should contain:

Component Name

Part Number

Quantity

Cupboard Number

The interface should clearly show the cupboard number field because it is required for locating the physical component.

Form validation

Validate:

Component Name cannot be empty

Part Number cannot be empty

Quantity must be numeric

Quantity cannot be negative

Cupboard Number cannot be empty

Show clean inline validation messages.

Buttons:

Save Component

Cancel

After successful saving:

Save the record to the database.

Show a success notification.

Close the form.

Refresh the component list/search data.

Make the newly added component immediately searchable.

7. DATABASE REQUIREMENTS

Use a proper persistent database.

Do NOT rely on browser localStorage as the primary database.

Create appropriate database structures for:

Users Table

Fields:

id

name

user_id

password_hash

created_at

updated_at

status

user_id must be unique.

Passwords should be stored securely using password hashing.

Components Table

Fields:

id

component_name

part_number

quantity

cupboard_number

created_by

created_at

updated_at

Add indexes for:

component_name

part_number

cupboard_number

The system should be designed so the component database can grow to thousands of records without becoming slow.

8. ADMIN LOGIN

Create a separate Admin Login entry.

The normal employee login should have a clearly visible but subtle option such as:

Admin Login

Do not mix the normal employee interface and admin authentication unnecessarily.

Initial Admin Credentials

For the first version, initialize the admin account with:

Admin ID: hpt_admin

Password: hpt_123456

IMPORTANT:

The password must NOT be displayed anywhere inside the application's normal interface.

Store it securely.

For a production deployment, structure the authentication so the administrator can change this initial password.

9. ADMIN PANEL

After successful admin authentication, redirect to:

HPT Admin Dashboard

The admin dashboard should look significantly different from the normal employee dashboard while maintaining the same branding.

Admin Dashboard

Include:

Dashboard Statistics

Show cards such as:

Total Users

Total Components

Total Quantity

Recently Added Components

These statistics should come from the database.

10. ADD USER

The admin panel must have a prominent button:

+ Add User

When clicked, open an Add User form.

The form must contain:

Name

Employee's full name

User ID

Unique login ID

Password

Initial password assigned to that employee

Buttons:

Create User

Cancel

Validation

Validate:

Name cannot be empty

User ID cannot be empty

User ID must be unique

Password cannot be empty

Password should meet a reasonable minimum length

After successful creation:

Save the user to the database

Hash the password

Show success notification

Add the user to the user list

Allow the newly created employee to log in immediately

11. ADMIN USER MANAGEMENT

Create a user-management section inside the admin dashboard.

Display a table containing:

NameUser IDStatusCreated DateActions

Admin should be able to:

Add user

View users

Activate/deactivate users

Reset/change user password

Delete user where appropriate

Never display stored passwords.

12. COMPONENT MANAGEMENT FOR ADMIN

The admin should also have access to all components.

Create an admin component-management section.

Display:

Component Name

Part Number

Quantity

Cupboard Number

Added By

Added Date

Actions

Admin should be able to:

Search components

Filter components

Edit component

Update quantity

Change cupboard number

Delete component if necessary

Normal users do not need destructive administrative controls.

13. SEARCH FUNCTIONALITY

Search must be practical for electronic components.

When users type:

resistor

Return all matching component names.

When users type:

10k

Return matching part numbers/components.

Implement:

Case-insensitive search

Partial text matching

Fast response

Search by component name

Search by part number

Example:

Searching:

LM358

Could return:

LM358

LM358P

LM358N

LM358DR

if these records exist in the database.

14. USER EXPERIENCE

The user interface must be extremely simple.

An employee should be able to:

Open the application

Enter User ID

Enter Password

Login

See the component search bar

Search a component

Immediately see part number, quantity and cupboard number

Add a new component when necessary

Avoid unnecessary complexity.

15. PROFESSIONAL UI DESIGN

The application should visually resemble a professional internal enterprise application used by an electronics company.

Design principles:

Clean spacing

Strong visual hierarchy

Rounded but professional cards

Subtle shadows

Minimal animations

Smooth transitions

Professional typography

Consistent button styles

Clear success/error notifications

Excellent table design

Responsive design

Desktop-first but fully mobile compatible

Do NOT use:

Excessive gradients

Neon colors

Cartoon illustrations

Gaming-style interfaces

Excessive glassmorphism

Unnecessary animations

Generic stock imagery

The brand should communicate:

Engineering + Reliability + Precision + Professionalism

16. LOGIN SCREEN DESIGN

Create a polished login screen.

Suggested structure:

Left side:

Harmony Powertech logo

Company name

Short statement such as:
"Electronic Component Management System"

Right side:

Login card

User ID

Password

Login button

Admin Login link

Use a modern professional layout with subtle engineering/technology visual elements.

Do not overcrowd the page.

17. RESPONSIVE DESIGN

The website must work correctly on:

Desktop

Laptop

Tablet

Mobile

The component search screen should remain easy to use on smaller screens.

Tables must become responsive.

Buttons should be touch-friendly.

18. NOTIFICATIONS

Use professional toast notifications.

Examples:

Success
"Component added successfully."

Error
"Unable to save component."

Authentication
"Invalid User ID or Password."

User Creation
"User created successfully."

Notifications should automatically disappear after a few seconds.

19. SECURITY

Implement proper authentication and authorization.

Requirements:

Password hashing

Protected routes

Session/token-based authentication

Admin-only routes

User-only routes

Logout functionality

Input validation

Server-side validation

Database validation

Prevent duplicate User IDs

Prevent unauthorized admin access

Never expose passwords in API responses

Never store plain-text passwords in the database

The initial admin credentials may be seeded during setup, but structure the system properly for production use.

20. API / BACKEND LOGIC

Create clean backend APIs for:

Authentication

Login user

Login admin

Logout

Session validation

Components

Add component

Search components

Get component

Update component

Delete component

Users

Create user

List users

Update user

Activate/deactivate user

Reset password

Delete user

Admin Dashboard

Get dashboard statistics

Use proper HTTP methods and meaningful API responses.

21. ERROR HANDLING

The application must gracefully handle:

Invalid login

Duplicate User ID

Duplicate/invalid component data

Database connection errors

Empty search

Invalid quantity

Unauthorized API calls

Expired sessions

Server errors

Never show raw database errors to users.

Display friendly messages.

22. LOGOUT

Both users and admin must have a clear logout button.

After logout:

Clear authentication session/token

Redirect to login page

Prevent use of browser back button to access protected pages without authentication

23. SEED DATA

For development/testing, create a small amount of sample component data.

Example:

ComponentPart NumberQuantityCupboard10K ResistorR-10K-0805500C-01100K ResistorR-100K-0805300C-011N4007 Diode1N4007150C-02LM358 ICLM358P80C-03100uF CapacitorCAP-100UF-25V120C-04

Clearly separate sample/demo data from production data so it can easily be removed.

24. PERFORMANCE

The application should be optimized for fast searches.

Search results should load quickly even when the database contains thousands of components.

Use:

Database indexes

Efficient queries

Pagination where appropriate

Debounced search input

Minimal unnecessary API requests

25. CODE QUALITY

Generate maintainable, modular code.

Separate:

Frontend

Backend

Database

Authentication

Components

Admin features

UI components

API services

Use reusable components instead of duplicating code.

Add meaningful comments only where necessary.

Do not produce a single huge file containing the entire application.

26. FINAL APPLICATION STRUCTURE

The final system should contain these main screens:

Public

User Login

Admin Login

User

Component Dashboard

Search Components

Add Component

User Profile / Account

Logout

Admin

Admin Dashboard

User Management

Add User

Component Management

Component Editing

System Statistics

Logout

27. IMPORTANT BUSINESS RULE

The most important requirement is:

Search results must come exclusively from the application's saved component database.

When a user adds:

Component Name = BC547

Part Number = BC547

Quantity = 100

Cupboard Number = C-05

and saves it, searching BC547 later must return that exact stored record.

The application must maintain persistent data after refresh and after users log out and log back in.

28. FINAL UI GOAL

Make the finished product look like an application that Harmony Powertech could genuinely deploy internally.

The visual impression should be:

Professional | Industrial | Engineering | Reliable | Modern | Clean

Use the uploaded Harmony Powertech logo as the central branding element and build the entire design system around its blue corporate identity.

The result must not look like a basic student project or generic CRUD dashboard.

Build the application completely, including frontend, backend, database, authentication, authorization, validation, responsive UI, admin panel, component management, and persistent storage.

Before considering the project complete, verify all major workflows:

User login

Invalid user login rejection

Admin login

Add user from admin panel

New user login

Add component

Search component

Search by part number

View quantity and cupboard number

Admin component management

Logout

Data persistence after page refresh

Protected admin routes

Responsive mobile layout

Do not leave placeholder buttons or unfinished pages.

This project was built with [Lovable](https://lovable.dev).

## Build with Lovable

Continue developing this project in the [Lovable editor](https://lovable.dev/projects/39043406-7b57-405d-92c2-cbd9ceb07ca7).

- **Ship faster**: describe what you want to build and Lovable handles the code.
- **Stay in sync**: every change made in Lovable is committed straight to this repository.
- **Full ownership**: this code is yours. Push to `main` on GitHub and your changes sync back into Lovable, ready for your next prompt.

## Development

Prefer working locally? You need Node.js and npm — [install with nvm](https://github.com/nvm-sh/nvm#installing-and-updating).

```sh
git clone <this-repository-url>
cd <repository-name>
npm i
npm run dev
```
"# hpt_component" 
"# Harmonypowertech_component" 
