///|
pub struct LimitedSizeMap[K, V] {
  capacity : Int
  values : Map[K, V]
  order : Array[K]
}

///|
pub fn[K : Eq + Hash, V] LimitedSizeMap::LimitedSizeMap(
  capacity : Int,
) -> LimitedSizeMap[K, V] {
  guard capacity > 0 else { panic() }
  { capacity, values: Map([]), order: [] }
}

///|
pub fn[K : Eq + Hash, V] LimitedSizeMap::get(
  self : LimitedSizeMap[K, V],
  key : K,
) -> V? {
  self.values.get(key)
}

///|
pub fn[K : Eq + Hash, V] LimitedSizeMap::set(
  self : LimitedSizeMap[K, V],
  key : K,
  value : V,
) -> Unit {
  if self.values.get(key) is None {
    self.order.push(key)
  }
  self.values[key] = value
  if self.order.length() > self.capacity {
    let oldest = self.order.remove(0)
    self.values.remove(oldest) |> ignore
  }
}

///|
pub fn[K : Eq + Hash, V] LimitedSizeMap::remove(
  self : LimitedSizeMap[K, V],
  key : K,
) -> V? {
  if self.order.search_by(existing => existing == key) is Some(index) {
    self.order.remove(index) |> ignore
  }
  let result = self.values.get(key)
  self.values.remove(key)
  result
}

///|
pub fn[K, V] LimitedSizeMap::length(self : LimitedSizeMap[K, V]) -> Int {
  self.order.length()
}

///|
pub(all) struct TranslationRecord {
  original_content : String
  reply_message_id : @model.MessageId
} derive(Debug)
