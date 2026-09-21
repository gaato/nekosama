///|
/// Per-guild settings persisted as JSON.
///
/// The file keeps the layout of the Python bot's `data/config.json`
/// (`{ "<guild id>": { "<key>": <value> } }`, ids as JSON numbers), so a
/// deployment can carry its data directory over unchanged.
pub struct ConfigStore {
  path : String
  data : Map[String, Map[String, Json]]
  save_lock : @async.Mutex
}

///|
const CONFIG_FILE_NAME : String = "config.json"

///|
/// A store that starts empty. `load` is the constructor for real use.
pub fn ConfigStore::ConfigStore(path : String) -> ConfigStore {
  { path, data: Map([]), save_lock: @async.Mutex(), }
}

///|
/// The data directory comes from `NEKOSAMA_DATA_DIR` and defaults to `data`.
pub fn config_path() -> String {
  let dir = @env.get_env_var("NEKOSAMA_DATA_DIR").unwrap_or("data")
  "\{dir}/\{CONFIG_FILE_NAME}"
}

///|
pub async fn ConfigStore::load(path : String) -> ConfigStore {
  let store = ConfigStore(path)
  if @fs.exists(path) {
    store.replace_with(@json.parse(@fs.read_file(path).text()))
  } else {
    // Write now so a data directory the bot cannot write to stops it at
    // startup, not at the first setting change.
    store.save()
  }
  store
}

///|
fn ConfigStore::replace_with(self : ConfigStore, json : Json) -> Unit {
  self.data.clear()
  guard json is Object(guilds) else { return }
  for guild_id, settings in guilds {
    if settings is Object(entries) {
      self.data[guild_id] = entries.copy()
    }
  }
}

///|
/// Guilds whose settings are empty are left out, as the Python bot did.
fn ConfigStore::to_json_value(self : ConfigStore) -> Json {
  let guilds : Map[String, Json] = Map([])
  for guild_id, settings in self.data {
    if !settings.is_empty() {
      guilds[guild_id] = Json::object(settings)
    }
  }
  Json::object(guilds)
}

///|
pub fn ConfigStore::get(
  self : ConfigStore,
  guild_id : @model.GuildId,
  key : String,
) -> Json? {
  match self.data.get("\{guild_id}") {
    Some(settings) => settings.get(key)
    None => None
  }
}

///|
/// Every setting of one guild, for display.
pub fn ConfigStore::guild(
  self : ConfigStore,
  guild_id : @model.GuildId,
) -> Map[String, Json] {
  self.data.get("\{guild_id}").unwrap_or(Map([]))
}

///|
/// The guilds that have any setting stored under `key`.
pub fn ConfigStore::guilds_with(
  self : ConfigStore,
  key : String,
) -> Array[@model.GuildId] {
  let guilds = []
  for raw, settings in self.data {
    if settings.contains(key) {
      let guild_id : @model.GuildId? = Some(@model.Id::parse(raw)) catch {
        _ => None
      }
      if guild_id is Some(guild_id) {
        guilds.push(guild_id)
      }
    }
  }
  guilds
}

///|
pub async fn ConfigStore::set(
  self : ConfigStore,
  guild_id : @model.GuildId,
  key : String,
  value : Json,
) -> Unit {
  let raw = "\{guild_id}"
  match self.data.get(raw) {
    Some(settings) => settings[key] = value
    None => self.data[raw] = Map::from_array([(key, value)])
  }
  self.save()
}

///|
pub async fn ConfigStore::remove(
  self : ConfigStore,
  guild_id : @model.GuildId,
  key : String,
) -> Unit {
  guard self.data.get("\{guild_id}") is Some(settings) && settings.contains(key) else {
    return
  }
  settings.remove(key)
  self.save()
}

///|
/// Write to a sibling file and rename it over the target, so a crash never
/// leaves a truncated config behind.
async fn ConfigStore::save(self : ConfigStore) -> Unit {
  self.save_lock.acquire()
  defer self.save_lock.release()
  // mkdir fails on an existing directory even with recursive=true.
  if parent_directory(self.path) is Some(dir) && !@fs.exists(dir) {
    @fs.mkdir(dir, recursive=true)
  }
  let tmp = "\{self.path}.tmp"
  @fs.write_file(tmp, self.to_json_value().stringify(indent=2))
  @fs.rename(tmp, self.path, replace=true)
}

///|
fn parent_directory(path : String) -> String? {
  match path.rev_find("/") {
    Some(index) if index > 0 => Some(path[:index].to_owned())
    _ => None
  }
}

///|
/// Snowflakes are stored as JSON numbers. `repr` keeps all 19 digits, which a
/// Double cannot.
pub fn[M] id_to_json(id : @model.Id[M]) -> Json {
  Json::number(0.0, repr="\{id}")
}

///|
/// Read a snowflake written by either bot: a JSON number or a string.
pub fn[M] id_from_json(json : Json) -> @model.Id[M]? {
  let raw = match json {
    Number(_, repr=Some(repr)) => repr
    Number(value, repr=None) => value.to_int64().to_string()
    String(text) => text
    _ => return None
  }
  Some(@model.Id::parse(raw)) catch {
    _ => None
  }
}

///|
pub fn[M] ConfigStore::get_id(
  self : ConfigStore,
  guild_id : @model.GuildId,
  key : String,
) -> @model.Id[M]? {
  match self.get(guild_id, key) {
    Some(json) => id_from_json(json)
    None => None
  }
}

///|
pub fn ConfigStore::get_bool(
  self : ConfigStore,
  guild_id : @model.GuildId,
  key : String,
  default~ : Bool,
) -> Bool {
  match self.get(guild_id, key) {
    Some(True) => true
    Some(False) => false
    _ => default
  }
}
