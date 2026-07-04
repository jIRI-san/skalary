// Domain layer: the pure core. It INTENTIONALLY imports Infrastructure, which is the
// architecture violation the locked ts-arch contract must detect (Domain -> Infrastructure).
import { Database } from "../infrastructure/database";

export class Order {
  private readonly db = new Database();

  place(id: string): void {
    this.db.save(id);
  }
}
