/// Database configuration, registered as a `configFactories` entry.
///
/// Magic core no longer merges a database default, so an app that registers
/// `DatabaseServiceProvider` lists this factory (or its own `database` map) in
/// `Magic.init(configFactories: [...])`. Without it the manager still opens
/// `magic_app.db` on the `sqlite` connection.
///
/// The database file lives in the application documents directory on native
/// platforms; on web it is backed by `sqlite3.wasm` and IndexedDB.
Map<String, dynamic> get databaseConfig => {
  'database': {
    'default': 'sqlite',
    'connections': {
      'sqlite': {'driver': 'sqlite', 'database': 'magic_app.db', 'prefix': ''},
    },
  },
};
