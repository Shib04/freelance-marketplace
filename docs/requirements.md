# Freelance Marketplace – Requirements Specification

## 1. Introduction

The purpose of this project is to design and develop a web-based freelancing marketplace that connects clients and freelancers.

Clients can publish projects, freelancers can find suitable projects and submit proposals, and clients can review proposals and select freelancers.

## 2. System Actors

- **Client:** A user who publishes projects and selects freelancers.
- **Freelancer:** A user who creates a professional profile and submits proposals for projects.
- **Administrator:** A user responsible for managing and monitoring the platform.

## 3. Functional Requirements

### 3.1 User Account and Profile Management

- **FR-01:** The system shall allow users to register using their name, email address, and password.
- **FR-02:** The system shall allow registered users to log in and log out.
- **FR-03:** The system shall allow users to select their role as a client or freelancer.
- **FR-04:** The system shall allow users to view and edit their profile information, including their name, profile picture, and personal description.
- **FR-05:** The system shall allow freelancers to add and edit their professional information, including skills, work experience, and education.
- **FR-06:** The system shall allow freelancers to add, edit, and delete portfolio items containing a title, description, and related file or link.

### 3.2 Project Management

- **FR-07:** The system shall allow clients to create projects by providing a title, description, required skills, budget, and deadline.
- **FR-08:** The system shall display published projects to freelancers.
- **FR-09:** The system shall allow clients to edit their projects or remove them from the list of active projects.
- **FR-10:** The system shall allow freelancers to search for projects by title or required skills.
- **FR-11:** The system shall allow freelancers to filter projects by criteria such as category, budget, and deadline.

### 3.3 Proposal Management

- **FR-12:** The system shall allow freelancers to submit proposals for active projects. Each proposal shall include a description, proposed price, and estimated completion time.
- **FR-13:** The system shall allow clients to view and review proposals submitted for their projects.
- **FR-14:** The system shall allow clients to view freelancers' profiles and portfolios to evaluate and compare proposals.
- **FR-15:** The system shall allow clients to select one of the freelancers who submitted a proposal.

### 3.4 Communication and Collaboration

- **FR-16:** The system shall provide a messaging feature that allows clients and freelancers to communicate about project details.
- **FR-17:** The system shall display project statuses, including active, in progress, and completed.
- **FR-18:** The system shall allow clients to submit a rating and review of a freelancer after project completion.

## 4. Non-Functional Requirements

- **NFR-01 – Security:** User passwords shall be stored using a secure password-hashing algorithm and shall never be stored as plain text.
- **NFR-02 – Access Control:** The system shall restrict access to features and data according to user roles and ownership. For example, a client shall only be allowed to edit projects created by their own account.
- **NFR-03 – Performance:** Under normal operating conditions, the system shall respond to common requests, such as viewing project lists and user profiles, within 3 seconds.
- **NFR-04 – Compatibility:** The user interface shall work correctly on commonly used web browsers and different screen sizes, including desktop and mobile devices.
- **NFR-05 – Usability:** The interface shall be simple and understandable, allowing users to perform main activities without specialized training.
- **NFR-06 – Privacy:** Users' personal information shall be protected against unauthorized access. Only information designated as public shall be visible to other users.

## 5. Minimum Viable Product (MVP)

The initial version of the system shall include:

1. User registration, login, and logout.
2. User role selection.
3. User profile creation and editing.
4. Freelancer skills and portfolio management.
5. Project creation, editing, and deactivation.
6. Project browsing, searching, and filtering.
7. Proposal submission.
8. Proposal review by clients.
9. Viewing freelancer profiles and portfolios.
10. Freelancer selection.
11. Messaging between clients and freelancers.
12. Project status tracking.

## 6. Future Enhancements

The following features are proposed for future versions:

1. Online payment and digital wallet.
2. Secure and milestone-based payments.
3. Dispute resolution system.
4. Notifications for new proposals, messages, and project status changes.
5. Two-way rating and review system.
6. Advanced user identity verification.
7. Advanced project management with milestones and separate deliverables.
8. Administrative reports and statistics.

## 7. Open Questions for the Client

- **Q-01:** Should a user be allowed to act as both a client and a freelancer using one account, or should each account have only one role?
- **Q-02:** Should payments be made directly between clients and freelancers, or should the platform receive and hold payments until the client approves the completed work?
- **Q-03:** After a freelancer submits completed work, should the client be allowed to approve it or request revisions? If so, should there be a limit on revision requests?
- **Q-04:** Is phone number or identity verification required for registration, or is email and password registration sufficient?

## 8. Assumptions and Scope

- The system will be developed as a web application.
- Clients and freelancers are the main user roles.
- Administrators are responsible for platform management and monitoring.
- Online payments, dispute resolution, and advanced identity verification are not included in the initial version unless otherwise requested by the client.
- The final details of payment, delivery, and revision processes will be determined after receiving the client's feedback.
