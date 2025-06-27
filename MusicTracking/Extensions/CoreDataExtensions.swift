import Foundation
import CoreData
import MusicKit

extension NSManagedObjectContext {
    
    public func saveIfChanged() throws {
        guard hasChanges else { return }
        try save()
    }
    
    public func performAndSave<T>(_ block: () throws -> T) throws -> T {
        let result = try block()
        try saveIfChanged()
        return result
    }
    
    public func performAndSaveAsync<T>(_ block: @escaping () throws -> T) async throws -> T {
        return try await perform {
            let result = try block()
            try self.saveIfChanged()
            return result
        }
    }
    
    public func findOrCreate<T: NSManagedObject>(
        entity: T.Type,
        predicate: NSPredicate
    ) throws -> T {
        let request = NSFetchRequest<T>(entityName: String(describing: entity))
        request.predicate = predicate
        request.fetchLimit = 1
        
        if let existingObject = try fetch(request).first {
            return existingObject
        } else {
            return T(context: self)
        }
    }
    
    public func countObjects<T: NSManagedObject>(
        ofType entity: T.Type,
        matching predicate: NSPredicate? = nil
    ) throws -> Int {
        let request = NSFetchRequest<T>(entityName: String(describing: entity))
        request.predicate = predicate
        request.includesSubentities = false
        request.includesPropertyValues = false
        
        return try count(for: request)
    }
    
    public func deleteAllObjects<T: NSManagedObject>(ofType entity: T.Type) throws {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: String(describing: entity))
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        deleteRequest.resultType = .resultTypeObjectIDs
        
        let result = try execute(deleteRequest) as? NSBatchDeleteResult
        let objectIDArray = result?.result as? [NSManagedObjectID]
        let changes = [NSDeletedObjectsKey: objectIDArray ?? []]
        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [self])
    }
}