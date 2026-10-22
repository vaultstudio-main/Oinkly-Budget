import SwiftData

/// The first shipped shape of the database, as 1.0 stored it. The models for it are frozen in `SchemaV1Models.swift`.
/// When a later release changes a model (adds, removes or renames a stored property), add a new schema that lists the
/// models as they are then, keep the old one as it is, and add a migration stage between them in
/// `PiggybankMigrationPlan`. Without that, an update could not open an existing database.
enum PiggybankSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [PiggybankSchemaV1.Account.self, PiggybankSchemaV1.Category.self, PiggybankSchemaV1.Transaction.self,
         PiggybankSchemaV1.Payee.self, PiggybankSchemaV1.Holding.self, PiggybankSchemaV1.HoldingEvent.self,
         PiggybankSchemaV1.Bill.self, PiggybankSchemaV1.Goal.self, PiggybankSchemaV1.GoalContribution.self,
         PiggybankSchemaV1.CustomPaymentMethod.self]
    }
}

/// The shape from 1.0 on. Adds primary checking, wire and digital routing numbers and an opening deposit flag, a tax
/// flag on categories, a remembered memo and method on payees, and three new models: splits, tags and recurring
/// transactions. Every new field has a default, so the move from V1 is automatic.
enum PiggybankSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Account.self, Category.self, Transaction.self, Payee.self, Holding.self, HoldingEvent.self,
         Bill.self, Goal.self, GoalContribution.self, CustomPaymentMethod.self,
         TransactionSplit.self, Tag.self, RecurringTransaction.self]
    }
}

/// Adds two models and nothing else: the person's own reminders and their saved CSV import layouts, which used to be kept
/// in each login's preferences. Every existing model is unchanged, so the move from V2 is automatic.
enum PiggybankSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        PiggybankSchemaV2.models + [ReminderRecord.self, ImportLayoutRecord.self]
    }
}

enum PiggybankMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [PiggybankSchemaV1.self, PiggybankSchemaV2.self, PiggybankSchemaV3.self] }
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: PiggybankSchemaV1.self, toVersion: PiggybankSchemaV2.self),
         .lightweight(fromVersion: PiggybankSchemaV2.self, toVersion: PiggybankSchemaV3.self)]
    }
}
