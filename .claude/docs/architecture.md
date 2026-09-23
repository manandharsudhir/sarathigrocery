You are working on an existing Flutter application.

Your task is to **refactor the project into a managed Clean Architecture using a feature-first approach**, while preserving all existing functionality.

## Main Goal

Transform the current project into a scalable structure where:

* Architecture is organized **by feature first**
* Each feature follows **Clean Architecture**
* Shared/core code is separated from feature-specific code
* Dependencies flow in the correct direction
* Existing behavior and UI must remain unchanged unless required
* Avoid unnecessary rewrites
* Keep the architecture practical and maintainable, not over-engineered

## IMPORTANT: Analyze Before Changing Anything

Before modifying code:

1. Inspect the entire project structure.
2. Identify:

   * Current folder structure
   * Existing features
   * State management
   * Routing
   * Dependency injection
   * API/networking
   * Models/entities
   * Repositories/services
   * Local storage/database
   * Shared widgets/utilities
   * Existing architectural patterns
3. Identify inconsistencies and architectural problems.
4. Determine which existing code can be reused/moved instead of rewritten.
5. Create a migration plan.

Do **not** immediately start moving files.

First provide a concise analysis containing:

* Current architecture
* Problems found
* Target architecture
* Migration strategy
* Important risks
* Files/features that should be migrated first

Then begin the migration.

---

# Target Architecture

Use a **feature-first Clean Architecture** structure similar to:

```text
lib/
├── app/
│   ├── app.dart
│   ├── router/
│   ├── theme/
│   └── config/
│
├── core/
│   ├── constants/
│   ├── errors/
│   ├── extensions/
│   ├── network/
│   ├── storage/
│   ├── utils/
│   ├── widgets/
│   └── services/
│
├── features/
│   ├── feature_a/
│   │   ├── data/
│   │   │   ├── datasources/
│   │   │   ├── models/
│   │   │   └── repositories/
│   │   │
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   ├── repositories/
│   │   │   └── usecases/
│   │   │
│   │   └── presentation/
│   │       ├── pages/
│   │       ├── widgets/
│   │       └── providers/
│   │
│   └── feature_b/
│       ├── data/
│       ├── domain/
│       └── presentation/
│
└── main.dart
```

Adapt this structure to the actual project instead of forcing unnecessary folders.

---

# Architecture Rules

## 1. Feature First

Features must be the primary organizational boundary.

Prefer:

```text
features/auth/
features/profile/
features/home/
features/settings/
```

instead of:

```text
screens/
models/
repositories/
services/
providers/
```

Do not create a global folder containing all feature-specific models, repositories, providers, etc.

---

## 2. Domain Layer

The domain layer must contain business logic and remain independent of Flutter/framework-specific implementation details.

Typical structure:

```text
domain/
├── entities/
├── repositories/
└── usecases/
```

Rules:

* Entities represent business concepts.
* Repository interfaces belong here.
* Use cases contain business operations.
* Domain should not depend on data or presentation.
* Avoid putting API/JSON/database concerns in domain entities.

Example:

```dart
abstract class UserRepository {
  Future<User> getUser();
}
```

---

## 3. Data Layer

The data layer implements domain contracts.

Typical structure:

```text
data/
├── datasources/
│   ├── remote/
│   └── local/
├── models/
└── repositories/
```

Responsibilities:

* API calls
* Database operations
* DTO/model conversion
* Serialization
* Repository implementations
* External services

Example:

```dart
class UserRepositoryImpl implements UserRepository {
  final UserRemoteDataSource remoteDataSource;

  UserRepositoryImpl(this.remoteDataSource);

  @override
  Future<User> getUser() async {
    final model = await remoteDataSource.getUser();
    return model.toEntity();
  }
}
```

---

## 4. Presentation Layer

Presentation should contain:

```text
presentation/
├── pages/
├── widgets/
└── providers/
```

Use the project's existing state-management approach rather than introducing a new one.

Keep:

* UI state
* UI-specific logic
* Providers/notifiers/controllers
* Page-level composition

out of the domain/data layers.

---

# State Management

Do NOT replace the existing state-management solution unless there is a strong architectural reason.

If the project already uses Riverpod:

* Keep Riverpod.
* Prefer modern Riverpod patterns already used by the project.
* Providers should generally live inside their feature.
* Avoid creating a giant global providers folder.
* Keep business logic in use cases/domain where appropriate.
* Providers should coordinate presentation with domain/data.

Example:

```text
features/auth/presentation/providers/
```

rather than:

```text
providers/auth_provider.dart
```

---

# Dependency Direction

Enforce:

```text
Presentation
      ↓
   Domain
      ↑
    Data
```

More precisely:

```text
Presentation → Domain
Data → Domain
```

Domain must NOT depend on:

```text
Flutter
Dio
Riverpod
Firebase
Drift
GraphQL
UI widgets
```

unless an existing project constraint makes this unavoidable.

---

# Shared Code

Put something in `core/` only if it is genuinely shared across multiple features.

Examples:

```text
core/network/
core/errors/
core/utils/
core/widgets/
core/constants/
```

Do NOT move feature-specific code into `core/` just because it is reused in one or two files.

If something belongs to a feature, keep it inside that feature.

---

# Dependency Injection

Inspect the existing dependency injection implementation.

Keep the existing DI approach if it is reasonable.

Organize registrations so feature dependencies remain understandable.

Avoid creating unnecessary abstractions solely to satisfy Clean Architecture.

---

# Models vs Entities

Keep API/database models inside `data/models`.

Keep business entities inside `domain/entities`.

When appropriate:

```dart
UserModel → User
```

Use mapping methods such as:

```dart
User toEntity()
```

and:

```dart
UserModel fromEntity(...)
```

Do not create duplicate entities/models when there is no meaningful architectural benefit.

---

# Repository Rules

Repository interfaces:

```text
domain/repositories/
```

Repository implementations:

```text
data/repositories/
```

The UI must not directly call:

```text
Dio
Firebase
GraphQL
Drift
HTTP clients
database APIs
```

unless that code is genuinely presentation-specific.

---

# Use Cases

Create use cases for meaningful business operations.

Good:

```text
Login
GetUserProfile
UpdateProfile
CreateOrder
GetOrders
CancelOrder
```

Avoid creating meaningless one-line use cases everywhere just for the sake of architecture.

For simple CRUD operations, use judgment based on the existing project's complexity.

The goal is **managed Clean Architecture**, not maximum abstraction.

---

# Migration Strategy

Migrate incrementally.

Do NOT attempt a massive rewrite of the entire application in one step.

Recommended process:

### Phase 1

Analyze the project and identify features.

### Phase 2

Create the new architectural foundation:

```text
app/
core/
features/
```

### Phase 3

Choose one representative feature and migrate it completely.

### Phase 4

Verify:

* Build
* Tests
* Routing
* State management
* API calls
* Dependency injection
* UI behavior

### Phase 5

Migrate remaining features one by one.

### Phase 6

Remove obsolete folders/files only after confirming there are no remaining references.

---

# Important Refactoring Rules

### Do

* Preserve existing functionality.
* Reuse working code.
* Move files carefully.
* Update imports automatically.
* Keep naming consistent.
* Keep architecture understandable.
* Prefer small, safe changes.
* Run formatting.
* Run static analysis.
* Run tests where available.
* Build/run the application after significant migrations.

### Do NOT

* Rewrite working business logic unnecessarily.
* Change UI designs.
* Change API contracts.
* Change backend behavior.
* Replace state management without justification.
* Introduce unnecessary packages.
* Create excessive abstractions.
* Create use cases for every trivial getter/setter.
* Put everything into `core`.
* Create huge global services.
* Leave duplicate old and new implementations without a reason.

---

# Naming

Follow the existing project's naming conventions where they are reasonable.

Use clear names such as:

```text
auth_repository.dart
auth_repository_impl.dart

login.dart
login_provider.dart

user_model.dart
user.dart

auth_remote_data_source.dart
```

Avoid vague names such as:

```text
manager.dart
helper.dart
common.dart
misc.dart
```

unless their purpose is genuinely clear.

---

# Error Handling

Inspect the existing error-handling approach first.

If needed, establish a consistent structure such as:

```text
core/errors/
├── exceptions.dart
└── failures.dart
```

Do not introduce a complicated error hierarchy unless the project benefits from it.

---

# Networking

Inspect the existing networking implementation.

If the project already uses Dio, GraphQL, Firebase, etc., keep it.

Network-specific implementation belongs in:

```text
features/<feature>/data/datasources/
```

or shared infrastructure under:

```text
core/network/
```

when genuinely shared.

---

# Routing

Keep routing centralized at the application level where appropriate:

```text
app/router/
```

But keep feature-specific route configuration close to the feature if that makes the project easier to maintain.

Do not duplicate route definitions.

---

# Output/Execution Rules

You are acting as a senior Flutter architect.

Work directly on the existing codebase.

Before each major migration:

1. Inspect relevant files.
2. Explain briefly what you are changing.
3. Make the smallest safe change.
4. Run analysis/tests/build where practical.
5. Fix issues caused by the migration.
6. Continue to the next feature.

Do not dump huge explanations.

Be concise and action-oriented.

When finished, provide:

```text
Migration Summary

Architecture:
- ...

Features migrated:
- ...

Shared/core changes:
- ...

Important changes:
- ...

Validation:
- flutter analyze: ...
- tests: ...
- build: ...

Remaining technical debt:
- ...
```

The final architecture should feel like a **real production Flutter application**, not a Clean Architecture tutorial project.

Prioritize:

**Maintainability > unnecessary abstraction**

**Feature isolation > global folders**

**Existing functionality > architectural perfection**

**Simple architecture > over-engineering**
