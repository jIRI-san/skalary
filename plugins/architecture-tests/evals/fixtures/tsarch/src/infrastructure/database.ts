// Infrastructure layer: a persistence detail the Domain layer must never depend on.
export class Database {
  save(record: string): void {
    // pretend this talks to a real datastore
    void record;
  }
}
