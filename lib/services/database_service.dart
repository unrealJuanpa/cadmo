
import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  late final Database _db;
  final Uuid _uuid = const Uuid();

  Future<void> initDb() async {
    final docDir = await getApplicationDocumentsDirectory();
    final cadmoDir = Directory(join(docDir.path, 'Cadmo'));

    if (!await cadmoDir.exists()) {
      await cadmoDir.create(recursive: true);
    }

    final path = join(cadmoDir.path, 'data.db');
    _db = sqlite3.open(path);

    _db.execute('''
      CREATE TABLE IF NOT EXISTS chat_index (
        uuid TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        configs TEXT,
        created_by TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS interactions (
        uuid TEXT PRIMARY KEY,
        chat_uuid TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        embedding TEXT NULL,
        sender TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        FOREIGN KEY (chat_uuid) REFERENCES chat_index (uuid)
      );
    ''');

    _db.execute('''
      CREATE TABLE IF NOT EXISTS configs (
        config_key TEXT PRIMARY KEY,
        config_value TEXT NOT NULL
      );
    ''');
  }

  Future<void> createNewChat(String title) async {
    final now = DateTime.now().toIso8601String();
    _db.execute(
      'INSERT INTO chat_index (uuid, title, created_at, updated_at) VALUES (?, ?, ?, ?)',
      [_uuid.v4(), title, now, now],
    );
  }

  Future<void> addInteraction(Map<String, dynamic> interaction) async {
    final now = DateTime.now().toIso8601String();
    _db.execute(
      'INSERT INTO interactions (uuid, chat_uuid, role, content, sender, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        _uuid.v4(),
        interaction['chat_uuid'],
        interaction['role'],
        interaction['content'],
        interaction['sender'],
        now,
        now,
      ],
    );
  }

  Future<List<Map<String, dynamic>>> getInteractions(String chatUuid, int limit) async {
    final ResultSet resultSet = _db.select(
      'SELECT role, content FROM interactions WHERE chat_uuid = ? ORDER BY created_at DESC LIMIT ?',
      [chatUuid, limit],
    );
    return resultSet.map((row) => {'role': row['role'], 'content': row['content']}).toList();
  }

  Future<List<Map<String, dynamic>>> getChats() async {
    final ResultSet resultSet = _db.select('SELECT uuid, title FROM chat_index ORDER BY updated_at DESC');
    return resultSet.map((row) => {'uuid': row['uuid'], 'title': row['title']}).toList();
  }
}
