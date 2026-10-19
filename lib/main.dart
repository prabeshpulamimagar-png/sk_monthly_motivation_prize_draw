import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';

// ============================================================
// 🎯 TARGET WINNERS MAP FOR EACH PRIZE AMOUNT
// - PRIZE AMOUNT : 'EMPLOYEE_CODE'
// - Yadi Employee Code halnubhayo bhane: Tyo manche le jitchha.
// - Yadi khali ('') chhodnubhayo bhane: RANDOM le jitchha.
// ============================================================
final Map<double, String> TARGET_WINNERS = {
  100.0: '', // Khali ('') = Pure Random
  200.0: '', // Khali ('') = Pure Random
  500.0: '', // Khali ('') = Pure Random
  1000.0: '', // Code rakhiyeko = Tyo specific manche le jitchha
};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      center: true,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const LuckyDrawApp());
}

const Color appGreen = Color(0xFF087F5B);
const Color darkBackground = Color(0xFF071B2B);
const Color cardBackground = Color(0xFF12384A);
const Color goldColor = Color(0xFFFFD166);

class LuckyDrawApp extends StatefulWidget {
  const LuckyDrawApp({super.key});

  @override
  State<LuckyDrawApp> createState() => _LuckyDrawAppState();
}

class _LuckyDrawAppState extends State<LuckyDrawApp> {
  bool isFullScreen = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyPress);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyPress);
    super.dispose();
  }

  bool _handleKeyPress(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f11) {
      _toggleFullScreen();
      return true;
    }
    return false;
  }

  Future<void> _toggleFullScreen() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      isFullScreen = await windowManager.isFullScreen();
      await windowManager.setFullScreen(!isFullScreen);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SK MONTHLY MOTIVATION PRIZE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: appGreen),
        scaffoldBackgroundColor: const Color(0xFFF4FAF8),
      ),
      home: const LuckyDrawPage(),
    );
  }
}

// ============================================================
// EMPLOYEE MODEL
// ============================================================

class Employee {
  final int sn;
  final String empCode;
  final String name;
  final String company;

  const Employee({
    required this.sn,
    required this.empCode,
    required this.name,
    required this.company,
  });

  factory Employee.fromMap(Map<String, Object?> map) {
    return Employee(
      sn: (map['sn'] as num?)?.toInt() ?? 0,
      empCode: (map['emp_code'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      company: (map['company'] ?? '').toString(),
    );
  }
}

// ============================================================
// WINNER HISTORY MODEL
// ============================================================

class WinnerRecord {
  final int id;
  final String empCode;
  final String name;
  final String company;
  final double prizeAmount;
  final String wonAt;

  const WinnerRecord({
    required this.id,
    required this.empCode,
    required this.name,
    required this.company,
    required this.prizeAmount,
    required this.wonAt,
  });

  factory WinnerRecord.fromMap(Map<String, Object?> map) {
    return WinnerRecord(
      id: (map['id'] as num?)?.toInt() ?? 0,
      empCode: (map['emp_code'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      company: (map['company'] ?? '').toString(),
      prizeAmount: (map['prize_amount'] as num?)?.toDouble() ?? 0,
      wonAt: (map['won_at'] ?? '').toString(),
    );
  }
}

// ============================================================
// DATABASE
// ============================================================

class EmployeeStore {
  EmployeeStore._();

  static final EmployeeStore instance = EmployeeStore._();

  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;

    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);

    final dbPath = p.join(directory.path, 'lucky_draw.db');

    _db = await openDatabase(
      dbPath,
      version: 2,
      onCreate: (database, version) async {
        await database.execute('''
            CREATE TABLE employees (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              sn INTEGER NOT NULL,
              emp_code TEXT NOT NULL UNIQUE,
              name TEXT NOT NULL,
              company TEXT NOT NULL
            )
          ''');

        await _createWinnersTable(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createWinnersTable(database);
        }
      },
    );

    return _db!;
  }

  static Future<void> _createWinnersTable(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
        CREATE TABLE IF NOT EXISTS winners (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          emp_code TEXT NOT NULL UNIQUE,
          name TEXT NOT NULL,
          company TEXT NOT NULL,
          prize_amount REAL NOT NULL,
          won_at TEXT NOT NULL
        )
      ''');
  }

  Future<List<Employee>> all() async {
    final database = await db;

    final rows = await database.query(
      'employees',
      orderBy: 'sn ASC, name COLLATE NOCASE ASC',
    );

    return rows.map(Employee.fromMap).toList();
  }

  Future<List<WinnerRecord>> history() async {
    final database = await db;

    final rows = await database.query(
      'winners',
      orderBy: 'id DESC',
    );

    return rows.map(WinnerRecord.fromMap).toList();
  }

  Future<Set<String>> winnerCodes() async {
    final database = await db;
    final rows = await database.query(
      'winners',
      columns: ['emp_code'],
    );

    return rows.map((row) => (row['emp_code'] ?? '').toString()).toSet();
  }

  Future<void> saveWinner({
    required Employee employee,
    required double prizeAmount,
  }) async {
    final database = await db;

    await database.insert(
      'winners',
      {
        'emp_code': employee.empCode,
        'name': employee.name,
        'company': employee.company,
        'prize_amount': prizeAmount,
        'won_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<void> deleteSingleWinner(int id) async {
    final database = await db;
    await database.delete(
      'winners',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static String cellText(Data? data) {
    if (data == null) return '';

    final dynamic cellValue = data.value;
    if (cellValue == null) return '';

    try {
      final dynamic rawValue = cellValue.value;
      if (rawValue == null) return '';
      return rawValue.toString().trim();
    } catch (_) {
      return cellValue.toString().trim();
    }
  }

  static String normalize(Object? value) {
    return (value ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static Map<String, int> _headerIndexes(List<Data?> row) {
    final indexes = <String, int>{};

    for (var i = 0; i < row.length; i++) {
      final header = normalize(cellText(row[i]));

      switch (header) {
        case 'sn':
        case 'sno':
        case 'slno':
        case 'serialno':
        case 'serialnumber':
        case 'serial':
          indexes['sn'] = i;
          break;

        case 'empcode':
        case 'employeeid':
        case 'employeecode':
        case 'employee':
          indexes['code'] = i;
          break;

        case 'name':
        case 'employeename':
          indexes['name'] = i;
          break;

        case 'company':
        case 'companyname':
          indexes['company'] = i;
          break;
      }
    }

    return indexes;
  }

  Future<int> importExcel(List<int> bytes) async {
    if (bytes.isEmpty) {
      throw Exception('Excel file is empty.');
    }

    final Excel workbook;

    try {
      workbook = Excel.decodeBytes(bytes);
    } catch (e) {
      throw Exception(
        'Could not read Excel file. '
        'Please select a valid .xlsx file. Details: $e',
      );
    }

    Sheet? selectedSheet;

    for (final sheet in workbook.tables.values) {
      if (sheet.rows.isNotEmpty) {
        selectedSheet = sheet;
        break;
      }
    }

    if (selectedSheet == null) {
      throw Exception('Excel worksheet is empty.');
    }

    final rows = selectedSheet.rows;
    Map<String, int> indexes = {};
    var headerRowIndex = -1;

    final searchLimit = min(rows.length, 15);

    for (var i = 0; i < searchLimit; i++) {
      final candidate = _headerIndexes(rows[i]);

      if (candidate.containsKey('code') &&
          candidate.containsKey('name') &&
          candidate.containsKey('company')) {
        indexes = candidate;
        headerRowIndex = i;
        break;
      }
    }

    if (headerRowIndex < 0) {
      throw Exception(
        'Excel header not found. '
        'Ensure the first header row has SL NO, EMPLOYEE ID, EMPLOYEE NAME, COMPANY.',
      );
    }

    final database = await db;
    var importedCount = 0;
    var generatedSn = 0;

    await database.transaction((txn) async {
      await txn.delete('employees');

      for (var i = headerRowIndex + 1; i < rows.length; i++) {
        final row = rows[i];

        String getCell(String key) {
          final index = indexes[key];

          if (index == null || index >= row.length) {
            return '';
          }

          return cellText(row[index]).trim();
        }

        var code = getCell('code');
        final name = getCell('name');
        final company = getCell('company');

        if (name.isEmpty) continue;

        generatedSn++;

        final excelSn = getCell('sn');
        final sn = int.tryParse(excelSn) ?? generatedSn;

        if (code.isEmpty) {
          code = 'TEMP_$sn';
        }

        await txn.insert(
          'employees',
          {
            'sn': sn,
            'emp_code': code,
            'name': name,
            'company': company,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        importedCount++;
      }
    });

    if (importedCount == 0) {
      throw Exception(
        'No employee data found. Please check rows with Employee ID and Name.',
      );
    }

    return importedCount;
  }
}

// ============================================================
// HOME PAGE
// ============================================================

class LuckyDrawPage extends StatefulWidget {
  const LuckyDrawPage({super.key});

  @override
  State<LuckyDrawPage> createState() => _LuckyDrawPageState();
}

class _LuckyDrawPageState extends State<LuckyDrawPage> {
  List<Employee> employees = [];
  List<WinnerRecord> winners = [];

  bool loading = true;
  bool importing = false;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    try {
      final employeeList = await EmployeeStore.instance.all();
      final historyList = await EmployeeStore.instance.history();

      if (!mounted) return;

      setState(() {
        employees = employeeList;
        winners = historyList;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      message('Database error: $e');
    }
  }

  Future<void> importExcel() async {
    if (importing) return;

    setState(() => importing = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      List<int>? bytes = file.bytes;

      if ((bytes == null || bytes.isEmpty) &&
          file.path != null &&
          file.path!.isNotEmpty) {
        bytes = await File(file.path!).readAsBytes();
      }

      if (bytes == null || bytes.isEmpty) {
        throw Exception('Could not read Excel file.');
      }

      final count = await EmployeeStore.instance.importExcel(bytes);

      await loadData();

      if (!mounted) return;
      message('$count employees imported (old master list replaced).');
    } catch (e) {
      message('Import failed:\n$e');
    } finally {
      if (mounted) {
        setState(() => importing = false);
      }
    }
  }

  void message(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          duration: const Duration(seconds: 7),
        ),
      );
  }

  Future<void> openDraw() async {
    if (employees.isEmpty) {
      message('Please import an Excel file first.');
      return;
    }

    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => const FullScreenDrawPage(),
      ),
    );

    await loadData();
  }

  @override
  Widget build(BuildContext context) {
    final wonCount = winners.length;
    final eligibleCount = max(0, employees.length - wonCount);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/sk_new_logo.jpeg',
              height: 42,
              errorBuilder: (_, __, ___) => const Icon(Icons.celebration),
            ),
            const SizedBox(width: 10),
            const Text(
              'SK MONTHLY MOTIVATION PRIZE',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Winner History',
            onPressed: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => const WinnerHistoryPage(),
                ),
              ).then((_) => loadData());
            },
            icon: const Icon(Icons.history),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.celebration,
                            color: appGreen,
                            size: 54,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'SK MONTHLY MOTIVATION PRIZE',
                            style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 32,
                            runSpacing: 16,
                            children: [
                              _stat('TOTAL EMPLOYEES', employees.length),
                              _stat('ELIGIBLE', eligibleCount),
                              _stat('WINNERS', wonCount),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              FilledButton.icon(
                                onPressed: importing ? null : importExcel,
                                icon: const Icon(Icons.upload_file),
                                label: Text(
                                  importing
                                      ? 'IMPORTING...'
                                      : 'IMPORT / UPDATE EXCEL',
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: loadData,
                                icon: const Icon(Icons.refresh),
                                label: const Text('REFRESH'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.push<void>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const WinnerHistoryPage(),
                                    ),
                                  ).then((_) => loadData());
                                },
                                icon: const Icon(Icons.history),
                                label: const Text('WINNER HISTORY'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Excel columns: SL NO | EMPLOYEE ID | EMPLOYEE NAME | COMPANY',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: employees.isEmpty
                          ? const Center(
                              child: Text(
                                'Employee list is empty.\nPlease import an Excel file.',
                                textAlign: TextAlign.center,
                              ),
                            )
                          : Column(
                              children: [
                                const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'EMPLOYEE LIST',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                                const Divider(height: 1),
                                Expanded(
                                  child: ListView.builder(
                                    itemCount: employees.length,
                                    itemBuilder: (context, index) {
                                      final person = employees[index];
                                      final alreadyWon = winners.any(
                                        (w) => w.empCode == person.empCode,
                                      );

                                      return ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor: alreadyWon
                                              ? Colors.orange.shade100
                                              : null,
                                          child: alreadyWon
                                              ? const Icon(
                                                  Icons.emoji_events,
                                                  color: Colors.deepOrange,
                                                )
                                              : Text('${index + 1}'),
                                        ),
                                        title: Text(person.name),
                                        subtitle: Text(
                                          '${person.empCode} • ${person.company}',
                                        ),
                                        trailing: alreadyWon
                                            ? const Chip(
                                                label: Text('WINNER'),
                                              )
                                            : null,
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 62,
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: employees.isEmpty ? null : openDraw,
                      icon: const Icon(Icons.celebration),
                      label: const Text(
                        'OPEN FULL SCREEN MONTHLY MOTIVATION PRIZE DRAW',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _stat(String title, int value) {
    return Column(
      children: [
        Text(
          '$value',
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.bold,
            color: appGreen,
          ),
        ),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

// ============================================================
// FULL SCREEN DRAW PAGE
// ============================================================

class FullScreenDrawPage extends StatefulWidget {
  const FullScreenDrawPage({super.key});

  @override
  State<FullScreenDrawPage> createState() => _FullScreenDrawPageState();
}

class _FullScreenDrawPageState extends State<FullScreenDrawPage> {
  final TextEditingController prizeController =
      TextEditingController(text: '100');

  final Random random = Random();

  List<Employee> employees = [];
  Set<String> wonCodes = {};

  Employee? displayEmployee;
  Employee? winner;

  Timer? animationTimer;

  bool loading = true;
  bool drawing = false;

  @override
  void initState() {
    super.initState();
    _enterFullscreen();
    loadData();
  }

  Future<void> _enterFullscreen() async {
    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        await windowManager.setFullScreen(true);
      } else {
        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.immersiveSticky,
        );
      }
    } catch (_) {}
  }

  Future<void> _restoreSystemUI() async {
    try {
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        await windowManager.setFullScreen(false);
      } else {
        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.edgeToEdge,
        );
      }
    } catch (_) {}
  }

  Future<void> loadData() async {
    try {
      final employeeList = await EmployeeStore.instance.all();
      final codes = await EmployeeStore.instance.winnerCodes();

      if (!mounted) return;

      setState(() {
        employees = employeeList;
        wonCodes = codes;
        displayEmployee = null;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      _message('Data loading failed: $e');
    }
  }

  List<Employee> get eligibleEmployees {
    return employees
        .where((employee) => !wonCodes.contains(employee.empCode))
        .toList();
  }

  Future<void> startDraw() async {
    if (drawing || loading) return;

    final amountText = prizeController.text.trim().replaceAll(',', '');
    final prizeAmount = double.tryParse(amountText);

    if (prizeAmount == null || prizeAmount <= 0) {
      _message('Please enter a valid Prize Amount (e.g., 100, 200).');
      return;
    }

    try {
      final latestEmployees = await EmployeeStore.instance.all();
      final latestWonCodes = await EmployeeStore.instance.winnerCodes();

      final candidates = latestEmployees
          .where((employee) => !latestWonCodes.contains(employee.empCode))
          .toList();

      if (!mounted) return;

      if (candidates.isEmpty) {
        setState(() {
          employees = latestEmployees;
          wonCodes = latestWonCodes;
        });
        _message('All employees have won! No eligible candidates left.');
        return;
      }

      setState(() {
        employees = latestEmployees;
        wonCodes = latestWonCodes;
        winner = null;
        displayEmployee = candidates.first;
        drawing = true;
      });

      animationTimer?.cancel();

      animationTimer = Timer.periodic(
        const Duration(milliseconds: 70),
        (_) {
          if (!mounted || candidates.isEmpty) return;

          setState(() {
            displayEmployee = candidates[random.nextInt(candidates.length)];
          });
        },
      );

      await Future<void>.delayed(const Duration(seconds: 4));

      if (!mounted) return;

      animationTimer?.cancel();
      animationTimer = null;

      // ----------------------------------------------------
      // 🎯 DYNAMIC TARGET MATCHING LOGIC
      // ----------------------------------------------------
      Employee selected;
      final targetCode = (TARGET_WINNERS[prizeAmount] ?? '').trim();

      if (targetCode.isNotEmpty) {
        final fixedCandidateIndex = candidates.indexWhere(
            (e) => e.empCode.trim().toLowerCase() == targetCode.toLowerCase());

        if (fixedCandidateIndex != -1) {
          selected = candidates[fixedCandidateIndex];
        } else {
          selected = candidates[random.nextInt(candidates.length)];
        }
      } else {
        selected = candidates[random.nextInt(candidates.length)];
      }

      try {
        await EmployeeStore.instance.saveWinner(
          employee: selected,
          prizeAmount: prizeAmount,
        );
      } catch (e) {
        if (!mounted) return;

        setState(() => drawing = false);
        await loadData();
        _message('Failed to save winner. Please try again. Details: $e');
        return;
      }

      if (!mounted) return;

      setState(() {
        winner = selected;
        displayEmployee = selected;
        wonCodes = {...wonCodes, selected.empCode};
        drawing = false;
      });

      await showCongratulations(
        selected,
        prizeAmount,
      );
    } catch (e) {
      if (!mounted) return;

      animationTimer?.cancel();
      animationTimer = null;

      setState(() => drawing = false);
      _message('Draw failed: $e');
    }
  }

  // FULL SCREEN CONGRATULATIONS DIALOG
  Future<void> showCongratulations(
    Employee person,
    double prizeAmount,
  ) async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.92),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.escape): () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).pop();
            },
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              backgroundColor: const Color(0xFF071B2B),
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Container(
                      width: double.infinity,
                      height: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 40, vertical: 28),
                      decoration: BoxDecoration(
                        color: const Color(0xFF102C3D),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: goldColor, width: 3),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 40,
                            spreadRadius: 10,
                          )
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.emoji_events,
                                color: goldColor,
                                size: 95,
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'CONGRATULATIONS!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: goldColor,
                                  fontSize: 42,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 3,
                                ),
                              ),
                            ],
                          ),
                          Expanded(
                            child: Center(
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 1000),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: double.infinity,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          person.name,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 84,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    Row(
                                      children: [
                                        Expanded(
                                            child: _winnerDetail(
                                                'EMP CODE', person.empCode)),
                                        const SizedBox(width: 20),
                                        Expanded(
                                            child: _winnerDetail(
                                                'COMPANY', person.company)),
                                      ],
                                    ),
                                    const SizedBox(height: 24),
                                    const Text(
                                      'YOU ARE THE LUCKY WINNER!',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 2,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'PRIZE AMOUNT',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    SizedBox(
                                      width: double.infinity,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          _formatAmount(prizeAmount),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: goldColor,
                                            fontSize: 84,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 550),
                                child: SizedBox(
                                  width: double.infinity,
                                  height: 64,
                                  child: FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: goldColor,
                                      foregroundColor: darkBackground,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    onPressed: () =>
                                        Navigator.pop(dialogContext),
                                    child: const Text(
                                      'CONTINUE',
                                      style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Press ESC key anytime to return to Home Page',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _winnerDetail(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 16,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Flexible(
            child: Text(
              value.isEmpty ? '-' : value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatAmount(double amount) {
    String value;
    if (amount == amount.roundToDouble()) {
      value = amount.toInt().toString();
    } else {
      value = amount.toStringAsFixed(2);
    }
    return '$value AED';
  }

  void _message(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          duration: const Duration(seconds: 6),
        ),
      );
  }

  @override
  void dispose() {
    animationTimer?.cancel();
    prizeController.dispose();
    _restoreSystemUI();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = eligibleEmployees.length;

    return Scaffold(
      backgroundColor: darkBackground,
      body: SafeArea(
        child: loading
            ? const Center(
                child: CircularProgressIndicator(color: goldColor),
              )
            : Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Back',
                          onPressed:
                              drawing ? null : () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Image.asset(
                          'assets/sk_new_logo.jpeg',
                          height: 46,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.celebration,
                            color: goldColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'SK MONTHLY MOTIVATION PRIZE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                        ),
                        Text(
                          'ELIGIBLE: $remaining',
                          style: const TextStyle(
                            color: goldColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          tooltip: 'Winner History',
                          onPressed: drawing
                              ? null
                              : () {
                                  Navigator.push<void>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const WinnerHistoryPage(),
                                    ),
                                  ).then((_) => loadData());
                                },
                          icon: const Icon(
                            Icons.history,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'WHO WILL BE THE NEXT WINNER?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: cardBackground,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: goldColor.withOpacity(0.5),
                            width: 2,
                          ),
                        ),
                        padding: const EdgeInsets.all(24),
                        child: remaining == 0
                            ? const Center(
                                child: Text(
                                  'ALL EMPLOYEES HAVE WON!',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: goldColor,
                                    fontSize: 30,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              )
                            : AnimatedSwitcher(
                                duration: const Duration(milliseconds: 60),
                                transitionBuilder: (child, animation) {
                                  return FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  );
                                },
                                child: _employeeDisplay(
                                  displayEmployee,
                                  drawing,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Icon(
                          Icons.card_giftcard,
                          color: goldColor,
                          size: 30,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'PRIZE AMOUNT',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 190,
                          child: TextField(
                            controller: prizeController,
                            enabled: !drawing,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: InputDecoration(
                              hintText: '100',
                              hintStyle: const TextStyle(
                                color: Colors.white38,
                              ),
                              filled: true,
                              fillColor: const Color(0xFF1B4658),
                              prefixText: ' ',
                              suffixText: ' ',
                              contentPadding: const EdgeInsets.all(12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 68,
                      child: FilledButton.icon(
                        onPressed: drawing || remaining == 0 ? null : startDraw,
                        style: FilledButton.styleFrom(
                          backgroundColor: goldColor,
                          foregroundColor: darkBackground,
                          disabledBackgroundColor: Colors.grey.shade700,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        icon: Icon(
                          drawing ? Icons.hourglass_top : Icons.celebration,
                          size: 30,
                        ),
                        label: Text(
                          drawing
                              ? 'DRAWING... PLEASE WAIT'
                              : remaining == 0
                                  ? 'NO EMPLOYEES LEFT'
                                  : 'START MONTHLY MOTIVATION PRIZE DRAW',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Press F11 to Toggle Fullscreen (Taskbar Hidden)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _employeeDisplay(Employee? person, bool isDrawing) {
    if (person == null) {
      return Column(
        key: const ValueKey('ready_placeholder'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(
            Icons.card_giftcard,
            color: goldColor,
            size: 80,
          ),
          SizedBox(height: 20),
          Text(
            'MONTHLY MOTIVATION PRIZE DRAW READY',
            style: TextStyle(
              color: goldColor,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Click "Start Monthly Motivation Prize Draw" to begin!',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
            ),
          ),
        ],
      );
    }

    return Column(
      key: ValueKey(
        '${person.empCode}_${isDrawing ? 'drawing' : 'idle'}',
      ),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          isDrawing ? Icons.autorenew : Icons.person,
          color: goldColor,
          size: 62,
        ),
        const SizedBox(height: 16),
        Text(
          isDrawing ? 'SELECTING EMPLOYEE...' : 'READY TO DRAW',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 16,
            letterSpacing: 2,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          person.empCode,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: goldColor,
            fontSize: 42,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          person.name,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 34,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          person.company.isEmpty ? '-' : person.company,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 21,
          ),
        ),
        const SizedBox(height: 22),
        if (isDrawing)
          const Text(
            'GOOD LUCK!',
            style: TextStyle(
              color: goldColor,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
            ),
          ),
      ],
    );
  }
}

// ============================================================
// WINNER HISTORY PAGE
// ============================================================

class WinnerHistoryPage extends StatefulWidget {
  const WinnerHistoryPage({super.key});

  @override
  State<WinnerHistoryPage> createState() => _WinnerHistoryPageState();
}

class _WinnerHistoryPageState extends State<WinnerHistoryPage> {
  List<WinnerRecord> records = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    loadHistory();
  }

  Future<void> loadHistory() async {
    try {
      final result = await EmployeeStore.instance.history();

      if (!mounted) return;

      setState(() {
        records = result;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load history: $e')),
      );
    }
  }

  Future<void> clearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear History'),
        content:
            const Text('Are you sure you want to clear all winner history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('DELETE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final database = await EmployeeStore.instance.db;
        await database.delete('winners');
        await loadHistory();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Winner history cleared.')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not clear history: $e')),
        );
      }
    }
  }

  Future<void> deleteSingleWinner(int id) async {
    try {
      await EmployeeStore.instance.deleteSingleWinner(id);
      await loadHistory();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Winner record deleted.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete winner: $e')),
      );
    }
  }

  String formatDate(String value) {
    try {
      final date = DateTime.parse(value).toLocal();

      String two(int number) => number.toString().padLeft(2, '0');

      return '${two(date.day)}/${two(date.month)}/${date.year} '
          '${two(date.hour)}:${two(date.minute)}';
    } catch (_) {
      return value;
    }
  }

  String formatAmount(double amount) {
    String value;
    if (amount == amount.roundToDouble()) {
      value = amount.toInt().toString();
    } else {
      value = amount.toStringAsFixed(2);
    }
    return '$value AED';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'WINNER HISTORY',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: loadHistory,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          IconButton(
            onPressed: records.isEmpty ? null : clearHistory,
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear History',
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : records.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.history,
                        size: 72,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'No winners yet.',
                        style: TextStyle(fontSize: 18),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.emoji_events,
                            color: appGreen,
                            size: 32,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'TOTAL WINNERS: ${records.length}',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: records.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final record = records[index];

                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 25,
                                    backgroundColor: Colors.amber.shade100,
                                    child: const Icon(
                                      Icons.emoji_events,
                                      color: Colors.deepOrange,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          record.name,
                                          style: const TextStyle(
                                            fontSize: 19,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          'Emp Code: ${record.empCode}',
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          'Company: ${record.company.isEmpty ? '-' : record.company}',
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          formatDate(record.wonAt),
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.redAccent,
                                          size: 22,
                                        ),
                                        tooltip: 'Delete this winner',
                                        onPressed: () =>
                                            deleteSingleWinner(record.id),
                                      ),
                                      const Text(
                                        'PRIZE',
                                        style: TextStyle(
                                          color: appGreen,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        formatAmount(record.prizeAmount),
                                        style: const TextStyle(
                                          color: appGreen,
                                          fontSize: 23,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
