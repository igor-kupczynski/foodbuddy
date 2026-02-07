import Foundation

enum MetadataConflictResolver {
    static func resolve<T: UpdatedAtVersioned>(local: T, remote: T) -> T {
        if remote.updatedAt >= local.updatedAt {
            return remote
        }
        return local
    }
}
