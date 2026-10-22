import SwiftData

/// The first shipped shape of the database, as 1.0 stored it. The models for it are frozen in `SchemaV1Models.swift`.
/// When a later release changes a model (adds, removes or renames a stored property), add a new schema that lists the
/// models as they are then, keep the old one as it is, and add a migration stage between them in
/// `OinklyBudgetMigrationPlan`. Without that, an update could not open an existing database.
enum OinklyBudgetSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [OinklyBudgetSchemaV1.Account.self, OinklyBudgetSchemaV1.Category.self, OinklyBudgetSchemaV1.Transaction.self,
         OinklyBudgetSchemaV1.Payee.self, OinklyBudgetSchemaV1.Holding.self, OinklyBudgetSchemaV1.HoldingEvent.self,
         OinklyBudgetSchemaV1.Bill.self, OinklyBudgetSchemaV1.Goal.self, OinklyBudgetSchemaV1.GoalContribution.self,
         OinklyBudgetSchemaV1.CustomPaymentMethod.self]
    }
}

/// The shape from 1.0 on. Adds primary checking, wire and digital routing numbers and an opening deposit flag, a tax
/// flag on categories, a remembered memo and method on payees, and three new models: splits, tags and recurring
/// transactions. Every new field has a default, so the move from V1 is automatic.
enum OinklyBudgetSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Account.self, Category.self, Transaction.self, Payee.self, Holding.self, HoldingEvent.self,
         Bill.self, Goal.self, GoalContribution.self, CustomPaymentMethod.self,
         TransactionSplit.self, Tag.self, RecurringTransaction.self]
    }
}

/// Adds two models and nothing else: the person's own reminders and their saved CSV import layouts, which used to be kept
/// in each login's preferences. Every existing model is unchanged, so the move from V2 is automatic.
enum OinklyBudgetSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OinklyBudgetSchemaV2.models + [ReminderRecord.self, ImportLayoutRecord.self]
    }
}

/// Adds one model and nothing else: the colour a person picked for an account's or a bill's default picture. Every
/// existing model is unchanged, so the move from V3 is automatic.
enum OinklyBudgetSchemaV4: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(4, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OinklyBudgetSchemaV3.models + [ArtworkChoice.self]
    }
}

enum OinklyBudgetMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [OinklyBudgetSchemaV1.self, OinklyBudgetSchemaV2.self, OinklyBudgetSchemaV3.self, OinklyBudgetSchemaV4.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: OinklyBudgetSchemaV1.self, toVersion: OinklyBudgetSchemaV2.self),
         .lightweight(fromVersion: OinklyBudgetSchemaV2.self, toVersion: OinklyBudgetSchemaV3.self),
         .lightweight(fromVersion: OinklyBudgetSchemaV3.self, toVersion: OinklyBudgetSchemaV4.self)]
    }
}
