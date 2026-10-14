import SwiftData

/// The first shipped shape of the database. When a later release changes a model (adds, removes or renames a stored
/// property), add a new `PiggybankSchemaV2` that lists the models as they are then, keep this one as it is, and add a
/// migration stage between them in `PiggybankMigrationPlan`. Without that, an update could not open an existing
/// database.
enum PiggybankSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Account.self, Category.self, Transaction.self, Payee.self, Holding.self, HoldingEvent.self,
         Bill.self, Goal.self, GoalContribution.self, CustomPaymentMethod.self]
    }
}

enum PiggybankMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [PiggybankSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
