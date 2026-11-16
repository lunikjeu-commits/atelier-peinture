import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kAppName = 'Atelier Peinture';
const String kVersion = '1.0.0';

/// Mettez votre nom ici pour qu'il s'affiche dans Réglages > À propos.
/// Exemple : const String kCreatorName = 'Jean Dupont';
const String kCreatorName = '';

// ═════════════════════════ Utilitaires ═════════════════════════

int _seq = 0;
String _newId() => '${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

double _parse(String s) =>
    double.tryParse(s.replaceAll(RegExp(r'\s'), '').replaceAll(',', '.')) ?? 0;

String _eur(double v) {
  final neg = v < -0.004;
  final parts = v.abs().toStringAsFixed(2).split('.');
  final digits = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('\u202F');
    buf.write(digits[i]);
  }
  return '${neg ? '-' : ''}$buf,${parts[1]}\u00A0€';
}

String _num(double v) {
  if (v == 0) return '';
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toString().replaceAll('.', ',');
}

String _fmtQty(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  var s = v.toStringAsFixed(2);
  if (s.endsWith('0')) s = s.substring(0, s.length - 1);
  return s.replaceAll('.', ',');
}

String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

const List<String> _weekdays = [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];
const List<String> _weekdaysShort = [
  'lun.',
  'mar.',
  'mer.',
  'jeu.',
  'ven.',
  'sam.',
  'dim.',
];
const List<String> _months = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];
const List<String> _monthsShort = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

String _dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? _parseDay(String? s) {
  if (s == null || s.isEmpty) return null;
  final d = DateTime.tryParse(s);
  if (d == null) return null;
  return DateTime(d.year, d.month, d.day);
}

int _daysBetween(DateTime a, DateTime b) => DateTime.utc(b.year, b.month, b.day)
    .difference(DateTime.utc(a.year, a.month, a.day))
    .inDays;

String _dateLong(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]} ${d.year}';

String _dateShort(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

// ═════════════════════════ Modèles ═════════════════════════

enum JobStatus { attente, enCours, termine }

String _statusLabel(JobStatus s) => s == JobStatus.attente
    ? 'En attente'
    : s == JobStatus.enCours
        ? 'En cours'
        : 'Terminé';

Color _statusBg(ColorScheme cs, JobStatus s) => s == JobStatus.attente
    ? cs.tertiaryContainer
    : s == JobStatus.enCours
        ? cs.primaryContainer
        : cs.secondaryContainer;

Color _statusFg(ColorScheme cs, JobStatus s) => s == JobStatus.attente
    ? cs.onTertiaryContainer
    : s == JobStatus.enCours
        ? cs.onPrimaryContainer
        : cs.onSecondaryContainer;

const Map<String, String> _photoKinds = {
  'avant': 'Véhicule : avant travaux',
  'apres': 'Travail terminé : après',
  'autre': 'Autres photos (détails, teinte…)',
};

class Photo {
  Photo({required this.id, required this.file, required this.kind});
  final String id;
  final String file;
  final String kind;

  Map<String, dynamic> toJson() => {'id': id, 'file': file, 'kind': kind};
  factory Photo.fromJson(Map<String, dynamic> j) => Photo(
        id: j['id'] as String,
        file: j['file'] as String,
        kind: (j['kind'] ?? 'autre') as String,
      );
}

class MixItem {
  MixItem({required this.name, required this.qty, required this.unit});
  String name;
  double qty;
  String unit;

  Map<String, dynamic> toJson() => {'name': name, 'qty': qty, 'unit': unit};
  factory MixItem.fromJson(Map<String, dynamic> j) => MixItem(
        name: (j['name'] ?? '') as String,
        qty: ((j['qty'] ?? 0) as num).toDouble(),
        unit: (j['unit'] ?? 'g') as String,
      );
}

class Job {
  Job({
    required this.id,
    this.lastName = '',
    this.firstName = '',
    this.phone = '',
    this.make = '',
    this.model = '',
    this.year = '',
    this.plate = '',
    this.colorRef = '',
    this.colorName = '',
    this.paintBrand = '',
    this.custom = false,
    List<MixItem>? mix,
    this.work = '',
    this.notes = '',
    this.quote = 0,
    this.plannedDate,
    this.doneDate,
    this.status = JobStatus.attente,
    List<Photo>? photos,
    String? createdAt,
  })  : mix = mix ?? [],
        photos = photos ?? [],
        createdAt = createdAt ?? DateTime.now().toIso8601String();

  final String id;
  String lastName;
  String firstName;
  String phone;
  String make;
  String model;
  String year;
  String plate;
  String colorRef;
  String colorName;
  String paintBrand;
  bool custom;
  final List<MixItem> mix;
  String work;
  String notes;
  double quote;
  String? plannedDate;
  String? doneDate;
  JobStatus status;
  final List<Photo> photos;
  final String createdAt;

  String get clientName {
    final n = '$lastName $firstName'.trim();
    return n.isEmpty ? 'Client sans nom' : n;
  }

  String get vehicleLabel {
    final v = '$make $model'.trim();
    return v.isEmpty ? 'Véhicule' : v;
  }

  Photo? get coverPhoto {
    for (final p in photos) {
      if (p.kind == 'apres') return p;
    }
    return photos.isEmpty ? null : photos.first;
  }

  bool matches(String q) {
    final t = q.trim().toLowerCase();
    if (t.isEmpty) return true;
    final hay = [
      lastName,
      firstName,
      phone,
      make,
      model,
      year,
      plate,
      colorRef,
      colorName,
      paintBrand,
      work,
      notes,
      ...mix.map((m) => m.name),
    ].join(' ').toLowerCase();
    return t.split(RegExp(r'\s+')).every((w) => hay.contains(w));
  }

  bool sameClient(Job o) {
    if (o.id == id) return false;
    final a = '${lastName.trim()} ${firstName.trim()}'.trim().toLowerCase();
    final b = '${o.lastName.trim()} ${o.firstName.trim()}'.trim().toLowerCase();
    if (a.isNotEmpty && a == b) return true;
    final p1 = _digits(phone);
    return p1.length >= 6 && p1 == _digits(o.phone);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'lastName': lastName,
        'firstName': firstName,
        'phone': phone,
        'make': make,
        'model': model,
        'year': year,
        'plate': plate,
        'colorRef': colorRef,
        'colorName': colorName,
        'paintBrand': paintBrand,
        'custom': custom,
        'mix': mix.map((m) => m.toJson()).toList(),
        'work': work,
        'notes': notes,
        'quote': quote,
        'plannedDate': plannedDate,
        'doneDate': doneDate,
        'status': status.name,
        'photos': photos.map((p) => p.toJson()).toList(),
        'createdAt': createdAt,
      };

  factory Job.fromJson(Map<String, dynamic> j) {
    String s(String k) => (j[k] ?? '') as String;
    return Job(
      id: j['id'] as String,
      lastName: s('lastName'),
      firstName: s('firstName'),
      phone: s('phone'),
      make: s('make'),
      model: s('model'),
      year: s('year'),
      plate: s('plate'),
      colorRef: s('colorRef'),
      colorName: s('colorName'),
      paintBrand: s('paintBrand'),
      custom: (j['custom'] ?? false) as bool,
      mix: ((j['mix'] ?? []) as List)
          .map((e) => MixItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      work: s('work'),
      notes: s('notes'),
      quote: ((j['quote'] ?? 0) as num).toDouble(),
      plannedDate: j['plannedDate'] as String?,
      doneDate: j['doneDate'] as String?,
      status: JobStatus.values.firstWhere(
        (e) => e.name == j['status'],
        orElse: () => JobStatus.attente,
      ),
      photos: ((j['photos'] ?? []) as List)
          .map((e) => Photo.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: j['createdAt'] as String?,
    );
  }
}

const List<String> _stockCategories = [
  'Abrasifs',
  'Diluants & solvants',
  'Masquage',
  'Mastic & apprêt',
  'Peintures & vernis',
  'Protection & nettoyage',
  'Autre',
];

const List<String> _stockUnits = [
  'pièce',
  'feuille',
  'rouleau',
  'boîte',
  'paquet',
  'L',
  'ml',
  'kg',
  'g',
];

double _stepFor(String unit) {
  if (unit == 'L' || unit == 'kg') return 0.5;
  if (unit == 'ml' || unit == 'g') return 100;
  return 1;
}

class StockItem {
  StockItem({
    required this.id,
    required this.name,
    this.category = 'Autre',
    this.qty = 0,
    this.unit = 'pièce',
    this.minQty = 0,
    this.fullQty = 0,
    this.note = '',
  });
  final String id;
  String name;
  String category;
  double qty;
  String unit;
  double minQty;
  double fullQty;
  String note;

  /// 'ok', 'bas' ou 'rupture'
  String get state {
    if (qty <= 0) return 'rupture';
    if (minQty > 0 && qty <= minQty) return 'bas';
    return 'ok';
  }

  double get fraction {
    var full = fullQty;
    if (full <= 0) {
      full = qty;
      if (minQty * 3 > full) full = minQty * 3;
      if (full < 1) full = 1;
    }
    final f = qty / full;
    return f < 0 ? 0 : (f > 1 ? 1 : f);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'qty': qty,
        'unit': unit,
        'minQty': minQty,
        'fullQty': fullQty,
        'note': note,
      };

  factory StockItem.fromJson(Map<String, dynamic> j) {
    final cat = (j['category'] ?? 'Autre') as String;
    final unit = (j['unit'] ?? 'pièce') as String;
    return StockItem(
      id: j['id'] as String,
      name: (j['name'] ?? '') as String,
      category: _stockCategories.contains(cat) ? cat : 'Autre',
      qty: ((j['qty'] ?? 0) as num).toDouble(),
      unit: _stockUnits.contains(unit) ? unit : 'pièce',
      minQty: ((j['minQty'] ?? 0) as num).toDouble(),
      fullQty: ((j['fullQty'] ?? 0) as num).toDouble(),
      note: (j['note'] ?? '') as String,
    );
  }
}

List<StockItem> _defaultStock() {
  StockItem s(String name, String cat, String unit, double min, double full) =>
      StockItem(
        id: _newId(),
        name: name,
        category: cat,
        unit: unit,
        minQty: min,
        fullQty: full,
      );
  return [
    s('Papier à poncer P80', 'Abrasifs', 'feuille', 10, 50),
    s('Papier à poncer P120', 'Abrasifs', 'feuille', 10, 50),
    s('Papier à poncer P240', 'Abrasifs', 'feuille', 10, 50),
    s('Papier à poncer P400', 'Abrasifs', 'feuille', 10, 50),
    s('Papier à poncer P800 (eau)', 'Abrasifs', 'feuille', 10, 50),
    s('Papier à poncer P1500 (eau)', 'Abrasifs', 'feuille', 10, 30),
    s('Diluant', 'Diluants & solvants', 'L', 1, 10),
    s('Dégraissant silicone', 'Diluants & solvants', 'L', 1, 5),
    s('Ruban de masquage 19 mm', 'Masquage', 'rouleau', 3, 20),
    s('Ruban de masquage 38 mm', 'Masquage', 'rouleau', 3, 20),
    s('Papier de masquage', 'Masquage', 'rouleau', 1, 5),
    s('Film de masquage', 'Masquage', 'rouleau', 1, 5),
    s('Mastic polyester', 'Mastic & apprêt', 'kg', 1, 5),
    s('Apprêt / primaire', 'Mastic & apprêt', 'L', 1, 5),
    s('Vernis', 'Peintures & vernis', 'L', 1, 5),
    s('Durcisseur', 'Peintures & vernis', 'L', 1, 5),
    s('Chiffons / lingettes', 'Protection & nettoyage', 'paquet', 2, 10),
    s('Gants nitrile', 'Protection & nettoyage', 'boîte', 1, 5),
  ];
}

// ═════════════════════════ Stockage / état ═════════════════════════

class AtelierStore extends ChangeNotifier {
  AtelierStore._(this._prefs, this.photosDir);

  static const _key = 'atelier_data_v1';
  final SharedPreferences _prefs;
  final String photosDir;

  final List<Job> jobs = [];
  final List<StockItem> stock = [];
  ThemeMode themeMode = ThemeMode.system;

  static Future<AtelierStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/photos');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final store = AtelierStore._(prefs, dir.path);
    final raw = prefs.getString(_key);
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        store._apply(j);
        final t = ((j['theme'] ?? 0) as num).toInt();
        store.themeMode = ThemeMode.values[t < 0 || t > 2 ? 0 : t];
      } catch (_) {
        // Données illisibles : on repart de zéro.
      }
    }
    return store;
  }

  void _apply(Map<String, dynamic> j) {
    final newJobs = <Job>[];
    final newStock = <StockItem>[];
    for (final e in (j['jobs'] ?? []) as List) {
      newJobs.add(Job.fromJson(e as Map<String, dynamic>));
    }
    for (final e in (j['stock'] ?? []) as List) {
      newStock.add(StockItem.fromJson(e as Map<String, dynamic>));
    }
    jobs
      ..clear()
      ..addAll(newJobs);
    stock
      ..clear()
      ..addAll(newStock);
  }

  Map<String, dynamic> _data() => {
        'app': 'atelier',
        'version': 1,
        'jobs': jobs.map((e) => e.toJson()).toList(),
        'stock': stock.map((e) => e.toJson()).toList(),
      };

  Future<void> _save() async {
    await _prefs.setString(
      _key,
      jsonEncode({..._data(), 'theme': themeMode.index}),
    );
  }

  void _changed() {
    notifyListeners();
    _save();
  }

  // ───── Sauvegarde ─────

  String exportBackup() => jsonEncode(_data());

  bool importBackup(String raw) {
    try {
      final j = jsonDecode(raw.trim());
      if (j is! Map<String, dynamic>) return false;
      if (j['app'] != 'atelier') return false;
      _apply(j);
      _changed();
      return true;
    } catch (_) {
      return false;
    }
  }

  void setTheme(ThemeMode m) {
    themeMode = m;
    _changed();
  }

  // ───── Dossiers ─────

  String photoPath(Photo p) => '$photosDir/${p.file}';

  Job? jobById(String id) {
    for (final j in jobs) {
      if (j.id == id) return j;
    }
    return null;
  }

  List<Job> get activeJobs =>
      jobs.where((j) => j.status != JobStatus.termine).toList();

  List<Job> get doneJobs {
    final list = jobs.where((j) => j.status == JobStatus.termine).toList();
    list.sort((a, b) {
      final c = (b.doneDate ?? '').compareTo(a.doneDate ?? '');
      return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }

  void _applyStatus(Job j, JobStatus s) {
    j.status = s;
    if (s == JobStatus.termine) {
      j.doneDate ??= _dayKey(_today());
    } else {
      j.doneDate = null;
    }
  }

  void saveJob(Job j, JobStatus status, {required bool isNew}) {
    if (isNew) jobs.add(j);
    _applyStatus(j, status);
    _changed();
  }

  void setStatus(Job j, JobStatus s) {
    _applyStatus(j, s);
    _changed();
  }

  Future<void> deleteJob(Job j) async {
    for (final p in j.photos) {
      try {
        await File(photoPath(p)).delete();
      } catch (_) {}
    }
    jobs.remove(j);
    _changed();
  }

  Future<void> addPhoto(Job job, File src, String kind) async {
    final id = _newId();
    final name = '$id.jpg';
    await src.copy('$photosDir/$name');
    job.photos.add(Photo(id: id, file: name, kind: kind));
    _changed();
  }

  Future<void> removePhoto(Job job, Photo p) async {
    try {
      await File(photoPath(p)).delete();
    } catch (_) {}
    job.photos.remove(p);
    _changed();
  }

  List<Job> otherJobsOf(Job job) {
    final list = jobs.where((o) => job.sameClient(o)).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  // ───── Stock ─────

  void addStock(StockItem s) {
    stock.add(s);
    _changed();
  }

  void updateStock(StockItem s) => _changed();

  void deleteStock(StockItem s) {
    stock.remove(s);
    _changed();
  }

  void adjustStock(StockItem s, double delta) {
    var q = s.qty + delta;
    if (q < 0) q = 0;
    s.qty = double.parse(q.toStringAsFixed(2));
    _changed();
  }

  void addDefaultStock() {
    stock.addAll(_defaultStock());
    _changed();
  }
}

// ═════════════════════════ Application ═════════════════════════

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await AtelierStore.load();
  runApp(AtelierApp(store: store));
}

class AtelierApp extends StatelessWidget {
  const AtelierApp({super.key, required this.store});
  final AtelierStore store;

  ThemeData _theme(Brightness b) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFD84315),
      brightness: b,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: const AppBarTheme(centerTitle: false),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => MaterialApp(
        title: kAppName,
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: store.themeMode,
        locale: const Locale('fr', 'FR'),
        supportedLocales: const [Locale('fr', 'FR')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: HomePage(store: store),
      ),
    );
  }
}

// ═════════════════════════ Outils d'interface ═════════════════════════

void _snack(BuildContext context, String msg, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), action: action));
}

Future<void> _sheet(BuildContext context, Widget child) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => child,
  );
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  String action = 'Supprimer',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
      ],
    ),
  );
  return ok == true;
}

final List<TextInputFormatter> _decimalOnly = [
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]')),
];

Widget _tf(
  TextEditingController c,
  String label, {
  TextInputType? type,
  TextCapitalization cap = TextCapitalization.sentences,
  int maxLines = 1,
  String? suffix,
  List<TextInputFormatter>? formatters,
  String? Function(String?)? validator,
  bool autofocus = false,
}) {
  return Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextFormField(
      controller: c,
      autofocus: autofocus,
      keyboardType: type ?? (maxLines > 1 ? TextInputType.multiline : null),
      textCapitalization: cap,
      minLines: maxLines > 1 ? 2 : 1,
      maxLines: maxLines,
      inputFormatters: formatters,
      decoration: InputDecoration(labelText: label, suffixText: suffix),
      validator: validator,
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    this.icon,
    this.trailing,
  });
  final String title;
  final IconData? icon;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: cs.primary, size: 22),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(title,
                      style: tt.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(label,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value,
                style: tt.bodyLarge?.copyWith(
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final JobStatus status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _statusBg(cs, status),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _statusLabel(status),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: _statusFg(cs, status), fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _PhotoImage extends StatelessWidget {
  const _PhotoImage({
    required this.store,
    required this.photo,
    this.cacheWidth,
    this.fit = BoxFit.cover,
  });
  final AtelierStore store;
  final Photo photo;
  final int? cacheWidth;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image.file(
      File(store.photoPath(photo)),
      fit: fit,
      cacheWidth: cacheWidth,
      errorBuilder: (context, error, stack) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.store, required this.job, this.size = 64});
  final AtelierStore store;
  final Job job;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = job.coverPhoto;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: size,
        height: size,
        child: p == null
            ? Container(
                color: cs.surfaceContainerHighest,
                alignment: Alignment.center,
                child: Icon(Icons.directions_car_outlined,
                    color: cs.onSurfaceVariant),
              )
            : _PhotoImage(store: store, photo: p, cacheWidth: 300),
      ),
    );
  }
}

// ═════════════════════════ Page d'accueil ═════════════════════════

Future<void> _openNewJob(
    BuildContext context, AtelierStore store, JobStatus status) async {
  final job = await Navigator.of(context).push<Job>(
    MaterialPageRoute<Job>(
        builder: (_) => JobFormPage(store: store, defaultStatus: status)),
  );
  if (job != null && context.mounted) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
          builder: (_) => JobDetailPage(store: store, jobId: job.id)),
    );
  }
}

void _openJob(BuildContext context, AtelierStore store, Job job) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
        builder: (_) => JobDetailPage(store: store, jobId: job.id)),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.store});
  final AtelierStore store;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  AtelierStore get store => widget.store;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    const titles = ['Planning', 'Dossiers', 'Stock'];
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        Widget? fab;
        if (_tab == 0) {
          fab = FloatingActionButton.extended(
            onPressed: () => _openNewJob(context, store, JobStatus.attente),
            icon: const Icon(Icons.add),
            label: const Text('Nouvelle fiche'),
          );
        } else if (_tab == 1) {
          fab = FloatingActionButton.extended(
            onPressed: () => _openNewJob(context, store, JobStatus.termine),
            icon: const Icon(Icons.add),
            label: const Text('Nouveau dossier'),
          );
        } else {
          fab = FloatingActionButton.extended(
            onPressed: () => _sheet(context, StockForm(store: store)),
            icon: const Icon(Icons.add),
            label: const Text('Nouvel article'),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(titles[_tab]),
            actions: [
              IconButton(
                tooltip: dark ? 'Mode clair' : 'Mode sombre',
                icon: Icon(
                    dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
                onPressed: () =>
                    store.setTheme(dark ? ThemeMode.light : ThemeMode.dark),
              ),
              IconButton(
                tooltip: 'Réglages',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => SettingsPage(store: store)),
                ),
              ),
            ],
          ),
          body: IndexedStack(
            index: _tab,
            children: [
              _PlanningTab(store: store),
              _DossiersTab(store: store),
              _StockTab(store: store),
            ],
          ),
          floatingActionButton: fab,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.event_note_outlined),
                  selectedIcon: Icon(Icons.event_note),
                  label: 'Planning'),
              NavigationDestination(
                  icon: Icon(Icons.folder_open_outlined),
                  selectedIcon: Icon(Icons.folder),
                  label: 'Dossiers'),
              NavigationDestination(
                  icon: Icon(Icons.inventory_2_outlined),
                  selectedIcon: Icon(Icons.inventory_2),
                  label: 'Stock'),
            ],
          ),
        );
      },
    );
  }
}

// ═════════════════════════ Onglet Planning ═════════════════════════

class _PlanningTab extends StatefulWidget {
  const _PlanningTab({required this.store});
  final AtelierStore store;

  @override
  State<_PlanningTab> createState() => _PlanningTabState();
}

class _PlanningTabState extends State<_PlanningTab> {
  DateTime? _selected;
  JobStatus? _filter;

  Widget _miniStat(BuildContext context, String label, int value, Color bg,
      Color fg) {
    final tt = Theme.of(context).textTheme;
    return Expanded(
      child: Card(
        color: bg,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              Text('$value',
                  style: tt.headlineSmall
                      ?.copyWith(color: fg, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(label,
                  textAlign: TextAlign.center,
                  style: tt.bodySmall?.copyWith(color: fg)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final today = _today();
    final all = store.activeJobs;

    final waiting = all.where((j) => j.status == JobStatus.attente).length;
    final running = all.where((j) => j.status == JobStatus.enCours).length;
    final overdue = all.where((j) {
      final d = _parseDay(j.plannedDate);
      return d != null && d.isBefore(today);
    }).length;

    var jobs = all;
    if (_filter != null) {
      jobs = jobs.where((j) => j.status == _filter).toList();
    }

    final days =
        List.generate(14, (i) => DateTime(today.year, today.month, today.day + i));

    final List<Widget> list = [];
    if (_selected != null) {
      final key = _dayKey(_selected!);
      final dayJobs = jobs.where((j) => j.plannedDate == key).toList()
        ..sort((a, b) => a.lastName.compareTo(b.lastName));
      list.add(Row(
        children: [
          Expanded(
            child: Text(
              _dateLong(_selected!),
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _selected = null),
            child: const Text('Tout afficher'),
          ),
        ],
      ));
      list.add(const SizedBox(height: 8));
      if (dayJobs.isEmpty) {
        list.add(Card.filled(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Rien de prévu ce jour-là.',
                textAlign: TextAlign.center,
                style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
          ),
        ));
      }
      for (final j in dayJobs) {
        list.add(Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _PlanningCard(store: store, job: j),
        ));
      }
    } else {
      final groups = <int, List<Job>>{};
      for (final j in jobs) {
        final d = _parseDay(j.plannedDate);
        int g;
        if (d == null) {
          g = 5;
        } else {
          final diff = _daysBetween(today, d);
          g = diff < 0
              ? 0
              : diff == 0
                  ? 1
                  : diff == 1
                      ? 2
                      : diff <= 7
                          ? 3
                          : 4;
        }
        groups.putIfAbsent(g, () => []).add(j);
      }
      const titles = [
        'En retard',
        'Aujourd’hui',
        'Demain',
        'Cette semaine',
        'Plus tard',
        'Sans date prévue',
      ];
      final keys = groups.keys.toList()..sort();
      for (final g in keys) {
        final items = groups[g]!;
        items.sort((a, b) {
          final c = (a.plannedDate ?? '').compareTo(b.plannedDate ?? '');
          return c != 0 ? c : a.lastName.compareTo(b.lastName);
        });
        list.add(Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            '${titles[g]} (${items.length})',
            style: tt.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: g == 0 ? cs.error : cs.onSurface),
          ),
        ));
        for (final j in items) {
          list.add(Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _PlanningCard(store: store, job: j),
          ));
        }
      }
      if (jobs.isEmpty) {
        list.add(Card.filled(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.event_available_outlined,
                    size: 48, color: cs.primary),
                const SizedBox(height: 12),
                Text(
                  'Aucune fiche en attente.\nAppuyez sur « Nouvelle fiche » pour planifier un travail.',
                  textAlign: TextAlign.center,
                  style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ));
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        Row(
          children: [
            _miniStat(context, 'En attente', waiting, cs.tertiaryContainer,
                cs.onTertiaryContainer),
            const SizedBox(width: 8),
            _miniStat(context, 'En cours', running, cs.primaryContainer,
                cs.onPrimaryContainer),
            const SizedBox(width: 8),
            _miniStat(
                context,
                'En retard',
                overdue,
                overdue > 0 ? cs.errorContainer : cs.surfaceContainerHighest,
                overdue > 0 ? cs.onErrorContainer : cs.onSurfaceVariant),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 86,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: days.length,
            separatorBuilder: (_, i) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final d = days[i];
              final key = _dayKey(d);
              final count = jobs.where((j) => j.plannedDate == key).length;
              final sel = _selected != null && _daysBetween(_selected!, d) == 0;
              final fg = sel ? cs.onPrimary : cs.onSurface;
              return InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => setState(() => _selected = sel ? null : d),
                child: Container(
                  width: 58,
                  decoration: BoxDecoration(
                    color: sel ? cs.primary : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(18),
                    border: i == 0 && !sel
                        ? Border.all(color: cs.primary, width: 1.5)
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_weekdaysShort[d.weekday - 1],
                          style: tt.bodySmall?.copyWith(color: fg)),
                      Text('${d.day}',
                          style: tt.titleLarge?.copyWith(
                              color: fg, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      count > 0
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 1),
                              decoration: BoxDecoration(
                                color: sel ? cs.onPrimary : cs.primary,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text('$count',
                                  style: tt.labelSmall?.copyWith(
                                      color: sel ? cs.primary : cs.onPrimary,
                                      fontWeight: FontWeight.bold)),
                            )
                          : const SizedBox(height: 16),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Tout'),
              selected: _filter == null,
              onSelected: (_) => setState(() => _filter = null),
            ),
            ChoiceChip(
              label: const Text('En attente'),
              selected: _filter == JobStatus.attente,
              onSelected: (_) => setState(() => _filter = JobStatus.attente),
            ),
            ChoiceChip(
              label: const Text('En cours'),
              selected: _filter == JobStatus.enCours,
              onSelected: (_) => setState(() => _filter = JobStatus.enCours),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...list,
      ],
    );
  }
}

class _PlanningCard extends StatelessWidget {
  const _PlanningCard({required this.store, required this.job});
  final AtelierStore store;
  final Job job;

  void _advance(BuildContext context) {
    if (job.status == JobStatus.attente) {
      store.setStatus(job, JobStatus.enCours);
    } else if (job.status == JobStatus.enCours) {
      store.setStatus(job, JobStatus.termine);
      _snack(
        context,
        'Dossier terminé : retrouvez-le dans l’onglet Dossiers',
        action: SnackBarAction(
          label: 'Annuler',
          onPressed: () => store.setStatus(job, JobStatus.enCours),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final d = _parseDay(job.plannedDate);
    final late = d != null && d.isBefore(_today());

    final badge = Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: late ? cs.errorContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: d == null
          ? Icon(Icons.event_busy_outlined, color: cs.onSurfaceVariant)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${d.day}',
                    style: tt.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: late ? cs.onErrorContainer : cs.onSurface)),
                Text(_monthsShort[d.month - 1],
                    style: tt.labelSmall?.copyWith(
                        color: late
                            ? cs.onErrorContainer
                            : cs.onSurfaceVariant)),
              ],
            ),
    );

    final colorLine = [job.colorRef, job.colorName]
        .where((s) => s.trim().isNotEmpty)
        .join(' · ');

    return Card.filled(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => _openJob(context, store, job),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  badge,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(job.clientName,
                            style: tt.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        Text(job.vehicleLabel, style: tt.bodyLarge),
                        if (colorLine.isNotEmpty)
                          Text(colorLine,
                              style: tt.bodyMedium
                                  ?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatusChip(job.status),
                ],
              ),
              if (job.work.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(job.work,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  if (job.quote > 0)
                    Text('Devis ${_eur(job.quote)}',
                        style: tt.titleSmall?.copyWith(
                            color: cs.primary, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    onPressed: () => _advance(context),
                    icon: Icon(job.status == JobStatus.attente
                        ? Icons.play_arrow
                        : Icons.check),
                    label: Text(job.status == JobStatus.attente
                        ? 'Démarrer'
                        : 'Terminer'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════ Onglet Dossiers ═════════════════════════

class _DossiersTab extends StatefulWidget {
  const _DossiersTab({required this.store});
  final AtelierStore store;

  @override
  State<_DossiersTab> createState() => _DossiersTabState();
}

class _DossiersTabState extends State<_DossiersTab> {
  final TextEditingController _c = TextEditingController();
  String _q = '';
  bool _onlyCustom = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final all = store.doneJobs;
    final jobs =
        all.where((j) => (!_onlyCustom || j.custom) && j.matches(_q)).toList();
    final total = jobs.fold(0.0, (s, j) => s + j.quote);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        TextField(
          controller: _c,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Client, modèle, plaque, référence couleur…',
            suffixIcon: _q.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _c.clear();
                      setState(() => _q = '');
                    },
                  ),
          ),
          onChanged: (v) => setState(() => _q = v),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            FilterChip(
              label: const Text('Compo perso'),
              avatar: const Icon(Icons.science_outlined, size: 18),
              selected: _onlyCustom,
              onSelected: (v) => setState(() => _onlyCustom = v),
            ),
            const Spacer(),
            Text(
              '${jobs.length} dossier${jobs.length > 1 ? 's' : ''} · ${_eur(total)}',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (jobs.isEmpty)
          Card.filled(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.folder_open_outlined, size: 48, color: cs.primary),
                  const SizedBox(height: 12),
                  Text(
                    all.isEmpty
                        ? 'Aucun dossier terminé pour le moment.\nTerminez une fiche du planning ou ajoutez un ancien travail.'
                        : 'Aucun dossier ne correspond à la recherche.',
                    textAlign: TextAlign.center,
                    style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          )
        else
          for (final j in jobs)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DossierCard(store: store, job: j),
            ),
      ],
    );
  }
}

class _DossierCard extends StatelessWidget {
  const _DossierCard({required this.store, required this.job});
  final AtelierStore store;
  final Job job;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final done = _parseDay(job.doneDate);
    final colorLine = [job.colorRef, job.colorName]
        .where((s) => s.trim().isNotEmpty)
        .join(' · ');
    return Card.filled(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => _openJob(context, store, job),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _Cover(store: store, job: job, size: 72),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(job.vehicleLabel,
                        style: tt.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text(job.clientName, style: tt.bodyMedium),
                    if (colorLine.isNotEmpty)
                      Text(colorLine,
                          style: tt.bodyMedium
                              ?.copyWith(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (done != null)
                          Text(_dateShort(done),
                              style: tt.bodySmall
                                  ?.copyWith(color: cs.onSurfaceVariant)),
                        if (job.custom) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.science_outlined,
                              size: 16, color: cs.primary),
                          const SizedBox(width: 2),
                          Text('Compo perso',
                              style: tt.bodySmall?.copyWith(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════ Fiche détaillée ═════════════════════════

String _mixTotals(List<MixItem> mix) {
  var g = 0.0;
  var ml = 0.0;
  for (final m in mix) {
    if (m.unit == 'ml') {
      ml += m.qty;
    } else {
      g += m.qty;
    }
  }
  final parts = <String>[];
  if (g > 0) parts.add('${_fmtQty(g)} g');
  if (ml > 0) parts.add('${_fmtQty(ml)} ml');
  return parts.join(' + ');
}

String _formulaText(Job j) {
  final b = StringBuffer();
  b.writeln('${j.vehicleLabel} : ${j.colorRef} ${j.colorName}'.trim());
  if (j.paintBrand.isNotEmpty) b.writeln('Marque : ${j.paintBrand}');
  for (final m in j.mix) {
    b.writeln('- ${m.name} : ${_fmtQty(m.qty)} ${m.unit}');
  }
  b.write('Total : ${_mixTotals(j.mix)}');
  return b.toString();
}

final ImagePicker _picker = ImagePicker();

Future<void> _pickPhotos(
    BuildContext context, AtelierStore store, Job job, String kind) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Prendre une photo'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choisir dans la galerie'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null) return;
  try {
    final List<XFile> files;
    if (source == ImageSource.camera) {
      final x = await _picker.pickImage(
          source: ImageSource.camera, imageQuality: 85, maxWidth: 1800);
      files = x == null ? <XFile>[] : <XFile>[x];
    } else {
      files = await _picker.pickMultiImage(imageQuality: 85, maxWidth: 1800);
    }
    for (final x in files) {
      await store.addPhoto(job, File(x.path), kind);
    }
  } catch (_) {
    if (context.mounted) {
      _snack(context, 'Impossible d’ajouter la photo');
    }
  }
}

class JobDetailPage extends StatelessWidget {
  const JobDetailPage({super.key, required this.store, required this.jobId});
  final AtelierStore store;
  final String jobId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final job = store.jobById(jobId);
        if (job == null) return const Scaffold(body: SizedBox.shrink());
        final cs = Theme.of(context).colorScheme;
        final tt = Theme.of(context).textTheme;
        final planned = _parseDay(job.plannedDate);
        final done = _parseDay(job.doneDate);
        final others = store.otherJobsOf(job);

        return Scaffold(
          appBar: AppBar(
            title: Text(job.clientName),
            actions: [
              IconButton(
                tooltip: 'Modifier',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<Job>(
                      builder: (_) => JobFormPage(
                          store: store,
                          job: job,
                          defaultStatus: job.status)),
                ),
              ),
              IconButton(
                tooltip: 'Supprimer',
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  final ok = await _confirm(
                    context,
                    title: 'Supprimer ce dossier ?',
                    message:
                        'La fiche et toutes ses photos seront définitivement supprimées.',
                  );
                  if (ok) {
                    await store.deleteJob(job);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // ───── Avancement ─────
              _Section(
                title: 'Avancement',
                icon: Icons.timeline,
                children: [
                  SegmentedButton<JobStatus>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                          value: JobStatus.attente, label: Text('En attente')),
                      ButtonSegment(
                          value: JobStatus.enCours, label: Text('En cours')),
                      ButtonSegment(
                          value: JobStatus.termine, label: Text('Terminé')),
                    ],
                    selected: {job.status},
                    onSelectionChanged: (s) => store.setStatus(job, s.first),
                  ),
                  const SizedBox(height: 8),
                  _InfoRow('Date prévue',
                      planned == null ? '' : _dateLong(planned)),
                  _InfoRow('Terminé le', done == null ? '' : _dateLong(done)),
                  _InfoRow('Devis', job.quote > 0 ? _eur(job.quote) : '',
                      bold: true),
                ],
              ),
              const SizedBox(height: 12),

              // ───── Client ─────
              _Section(
                title: 'Client',
                icon: Icons.person_outline,
                children: [
                  _InfoRow('Nom', job.lastName),
                  _InfoRow('Prénom', job.firstName),
                  if (job.phone.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 112,
                            child: Text('Téléphone',
                                style: tt.bodyMedium
                                    ?.copyWith(color: cs.onSurfaceVariant)),
                          ),
                          Expanded(
                            child: Text(job.phone,
                                style: tt.bodyLarge
                                    ?.copyWith(fontWeight: FontWeight.w600)),
                          ),
                          IconButton(
                            tooltip: 'Copier le numéro',
                            icon: const Icon(Icons.copy_outlined),
                            onPressed: () async {
                              await Clipboard.setData(
                                  ClipboardData(text: job.phone));
                              if (context.mounted) {
                                _snack(context, 'Numéro copié');
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // ───── Véhicule ─────
              _Section(
                title: 'Véhicule',
                icon: Icons.directions_car_outlined,
                children: [
                  _InfoRow('Marque', job.make),
                  _InfoRow('Modèle', job.model),
                  _InfoRow('Année', job.year),
                  _InfoRow('Immatriculation', job.plate),
                ],
              ),
              const SizedBox(height: 12),

              // ───── Peinture ─────
              _Section(
                title: 'Peinture',
                icon: Icons.format_paint_outlined,
                trailing: job.custom
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('Compo perso',
                            style: tt.labelMedium?.copyWith(
                                color: cs.onPrimaryContainer,
                                fontWeight: FontWeight.w700)),
                      )
                    : null,
                children: [
                  _InfoRow('Référence', job.colorRef, bold: true),
                  _InfoRow('Nom couleur', job.colorName),
                  _InfoRow('Marque', job.paintBrand),
                  if (job.colorRef.isEmpty &&
                      job.colorName.isEmpty &&
                      job.paintBrand.isEmpty &&
                      !job.custom)
                    Text('Aucune information de peinture.',
                        style: tt.bodyMedium
                            ?.copyWith(color: cs.onSurfaceVariant)),
                  if (job.custom) ...[
                    const SizedBox(height: 8),
                    Text('Composition',
                        style: tt.labelLarge
                            ?.copyWith(color: cs.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    if (job.mix.isEmpty)
                      Text('Aucun produit renseigné.', style: tt.bodyMedium),
                    for (final m in job.mix)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                                child: Text(m.name, style: tt.bodyLarge)),
                            Text('${_fmtQty(m.qty)} ${m.unit}',
                                style: tt.bodyLarge
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    if (job.mix.isNotEmpty) ...[
                      const Divider(),
                      Row(
                        children: [
                          Expanded(
                              child: Text('Total',
                                  style: tt.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w700))),
                          Text(_mixTotals(job.mix),
                              style: tt.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: cs.primary)),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () async {
                            await Clipboard.setData(
                                ClipboardData(text: _formulaText(job)));
                            if (context.mounted) {
                              _snack(context, 'Formule copiée');
                            }
                          },
                          icon: const Icon(Icons.copy_outlined),
                          label: const Text('Copier la formule'),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
              const SizedBox(height: 12),

              // ───── Travail ─────
              if (job.work.trim().isNotEmpty || job.notes.trim().isNotEmpty) ...[
                _Section(
                  title: 'Travail et notes',
                  icon: Icons.build_outlined,
                  children: [
                    if (job.work.trim().isNotEmpty) ...[
                      Text('Travail', style: tt.labelLarge
                          ?.copyWith(color: cs.onSurfaceVariant)),
                      Text(job.work, style: tt.bodyLarge),
                      const SizedBox(height: 8),
                    ],
                    if (job.notes.trim().isNotEmpty) ...[
                      Text('Notes', style: tt.labelLarge
                          ?.copyWith(color: cs.onSurfaceVariant)),
                      Text(job.notes, style: tt.bodyLarge),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
              ],

              // ───── Photos ─────
              _Section(
                title: 'Photos',
                icon: Icons.photo_camera_outlined,
                children: [
                  for (final e in _photoKinds.entries)
                    _PhotoGroup(
                        store: store, job: job, kind: e.key, label: e.value),
                ],
              ),

              // ───── Autres travaux du client ─────
              if (others.isNotEmpty) ...[
                const SizedBox(height: 12),
                _Section(
                  title: 'Autres travaux de ce client (${others.length})',
                  icon: Icons.history,
                  children: [
                    for (final o in others)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _Cover(store: store, job: o, size: 48),
                        title: Text(o.vehicleLabel),
                        subtitle: Text([
                          _statusLabel(o.status),
                          if (o.colorRef.isNotEmpty) o.colorRef,
                        ].join(' · ')),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openJob(context, store, o),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PhotoGroup extends StatelessWidget {
  const _PhotoGroup({
    required this.store,
    required this.job,
    required this.kind,
    required this.label,
  });
  final AtelierStore store;
  final Job job;
  final String kind;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final photos = job.photos.where((p) => p.kind == kind).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
            ),
            TextButton.icon(
              onPressed: () => _pickPhotos(context, store, job, kind),
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Ajouter'),
            ),
          ],
        ),
        if (photos.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('Aucune photo',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          )
        else
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, i) => const SizedBox(width: 8),
              itemBuilder: (context, i) => GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PhotoViewerPage(
                        store: store,
                        job: job,
                        kind: kind,
                        startId: photos[i].id),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 100,
                    height: 100,
                    child: _PhotoImage(
                        store: store, photo: photos[i], cacheWidth: 300),
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class PhotoViewerPage extends StatefulWidget {
  const PhotoViewerPage({
    super.key,
    required this.store,
    required this.job,
    required this.kind,
    required this.startId,
  });
  final AtelierStore store;
  final Job job;
  final String kind;
  final String startId;

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  late final PageController _controller;
  late int _index;

  List<Photo> get _photos =>
      widget.job.photos.where((p) => p.kind == widget.kind).toList();

  @override
  void initState() {
    super.initState();
    final idx = _photos.indexWhere((p) => p.id == widget.startId);
    _index = idx < 0 ? 0 : idx;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final photos = _photos;
    if (photos.isEmpty) return;
    final photo = photos[_index.clamp(0, photos.length - 1)];
    final ok = await _confirm(
      context,
      title: 'Supprimer cette photo ?',
      message: 'La photo sera définitivement supprimée.',
    );
    if (!ok) return;
    await widget.store.removePhoto(widget.job, photo);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final photos = _photos;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_index + 1} / ${photos.length}'),
        actions: [
          IconButton(
            tooltip: 'Supprimer',
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: photos.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Center(
            child: _PhotoImage(
              store: widget.store,
              photo: photos[i],
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════ Formulaire de fiche ═════════════════════════

class _MixRow {
  _MixRow({String name = '', String qty = '', this.unit = 'g'})
      : name = TextEditingController(text: name),
        qty = TextEditingController(text: qty);
  final TextEditingController name;
  final TextEditingController qty;
  String unit;

  void dispose() {
    name.dispose();
    qty.dispose();
  }
}

class JobFormPage extends StatefulWidget {
  const JobFormPage({
    super.key,
    required this.store,
    this.job,
    this.defaultStatus = JobStatus.attente,
  });
  final AtelierStore store;
  final Job? job;
  final JobStatus defaultStatus;

  @override
  State<JobFormPage> createState() => _JobFormPageState();
}

class _JobFormPageState extends State<JobFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _lastName;
  late final TextEditingController _firstName;
  late final TextEditingController _phone;
  late final TextEditingController _make;
  late final TextEditingController _model;
  late final TextEditingController _year;
  late final TextEditingController _plate;
  late final TextEditingController _colorRef;
  late final TextEditingController _colorName;
  late final TextEditingController _paintBrand;
  late final TextEditingController _work;
  late final TextEditingController _notes;
  late final TextEditingController _quote;
  late bool _custom;
  late JobStatus _status;
  DateTime? _planned;
  final List<_MixRow> _mix = [];

  @override
  void initState() {
    super.initState();
    final j = widget.job;
    _lastName = TextEditingController(text: j?.lastName ?? '');
    _firstName = TextEditingController(text: j?.firstName ?? '');
    _phone = TextEditingController(text: j?.phone ?? '');
    _make = TextEditingController(text: j?.make ?? '');
    _model = TextEditingController(text: j?.model ?? '');
    _year = TextEditingController(text: j?.year ?? '');
    _plate = TextEditingController(text: j?.plate ?? '');
    _colorRef = TextEditingController(text: j?.colorRef ?? '');
    _colorName = TextEditingController(text: j?.colorName ?? '');
    _paintBrand = TextEditingController(text: j?.paintBrand ?? '');
    _work = TextEditingController(text: j?.work ?? '');
    _notes = TextEditingController(text: j?.notes ?? '');
    _quote = TextEditingController(text: _num(j?.quote ?? 0));
    _custom = j?.custom ?? false;
    _status = j?.status ?? widget.defaultStatus;
    _planned = _parseDay(j?.plannedDate);
    if (j != null) {
      for (final m in j.mix) {
        _mix.add(_MixRow(name: m.name, qty: _num(m.qty), unit: m.unit));
      }
    }
  }

  @override
  void dispose() {
    for (final c in [
      _lastName,
      _firstName,
      _phone,
      _make,
      _model,
      _year,
      _plate,
      _colorRef,
      _colorName,
      _paintBrand,
      _work,
      _notes,
      _quote,
    ]) {
      c.dispose();
    }
    for (final r in _mix) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _planned ?? _today(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Date prévue',
      cancelText: 'Annuler',
      confirmText: 'OK',
    );
    if (picked != null) {
      setState(() => _planned = DateTime(picked.year, picked.month, picked.day));
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final mix = <MixItem>[];
    if (_custom) {
      for (final r in _mix) {
        final n = r.name.text.trim();
        final q = _parse(r.qty.text);
        if (n.isEmpty && q <= 0) continue;
        mix.add(MixItem(name: n.isEmpty ? 'Produit' : n, qty: q, unit: r.unit));
      }
    }
    final isNew = widget.job == null;
    final j = widget.job ?? Job(id: _newId());
    j.lastName = _lastName.text.trim();
    j.firstName = _firstName.text.trim();
    j.phone = _phone.text.trim();
    j.make = _make.text.trim();
    j.model = _model.text.trim();
    j.year = _year.text.trim();
    j.plate = _plate.text.trim().toUpperCase();
    j.colorRef = _colorRef.text.trim().toUpperCase();
    j.colorName = _colorName.text.trim();
    j.paintBrand = _paintBrand.text.trim();
    j.custom = _custom;
    j.mix
      ..clear()
      ..addAll(mix);
    j.work = _work.text.trim();
    j.notes = _notes.text.trim();
    j.quote = _parse(_quote.text);
    j.plannedDate = _planned == null ? null : _dayKey(_planned!);
    widget.store.saveJob(j, _status, isNew: isNew);
    Navigator.pop(context, j);
  }

  Widget _mixCard(int i) {
    final r = _mix[i];
    return Padding(
      key: ObjectKey(r),
      padding: const EdgeInsets.only(top: 12),
      child: Card.outlined(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              TextFormField(
                controller: r.name,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Produit (ex. Base noire, durcisseur)'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: r.qty,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: _decimalOnly,
                      decoration: const InputDecoration(labelText: 'Quantité'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'g', label: Text('g')),
                      ButtonSegment(value: 'ml', label: Text('ml')),
                    ],
                    selected: {r.unit},
                    onSelectionChanged: (s) => setState(() => r.unit = s.first),
                  ),
                  IconButton(
                    tooltip: 'Retirer',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() {
                      _mix.removeAt(i).dispose();
                    }),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isNew = widget.job == null;
    return Scaffold(
      appBar: AppBar(title: Text(isNew ? 'Nouvelle fiche' : 'Modifier la fiche')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _Section(
              title: 'Client',
              icon: Icons.person_outline,
              children: [
                _tf(_lastName, 'Nom',
                    cap: TextCapitalization.words,
                    autofocus: isNew,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Saisissez le nom du client'
                        : null),
                _tf(_firstName, 'Prénom', cap: TextCapitalization.words),
                _tf(_phone, 'Téléphone',
                    type: TextInputType.phone,
                    formatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+.\s-]')),
                    ]),
              ],
            ),
            const SizedBox(height: 12),
            _Section(
              title: 'Véhicule',
              icon: Icons.directions_car_outlined,
              children: [
                _tf(_make, 'Marque (ex. Peugeot)', cap: TextCapitalization.words),
                _tf(_model, 'Modèle (ex. 208)', cap: TextCapitalization.words),
                _tf(_year, 'Année',
                    type: TextInputType.number,
                    formatters: [FilteringTextInputFormatter.digitsOnly]),
                _tf(_plate, 'Immatriculation',
                    cap: TextCapitalization.characters),
              ],
            ),
            const SizedBox(height: 12),
            _Section(
              title: 'Peinture',
              icon: Icons.format_paint_outlined,
              children: [
                _tf(_colorRef, 'Référence couleur (ex. EXL)',
                    cap: TextCapitalization.characters),
                _tf(_colorName, 'Nom de la couleur',
                    cap: TextCapitalization.words),
                _tf(_paintBrand, 'Marque de peinture',
                    cap: TextCapitalization.words),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Composition personnalisée'),
                  subtitle: const Text('Pour noter les quantités de chaque produit'),
                  value: _custom,
                  onChanged: (v) => setState(() {
                    _custom = v;
                    if (v && _mix.isEmpty) _mix.add(_MixRow());
                  }),
                ),
                if (_custom) ...[
                  for (var i = 0; i < _mix.length; i++) _mixCard(i),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _mix.add(_MixRow())),
                      icon: const Icon(Icons.add),
                      label: const Text('Ajouter un produit'),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            _Section(
              title: 'Travail',
              icon: Icons.build_outlined,
              children: [
                _tf(_work, 'Travail à faire / effectué', maxLines: 5),
                _tf(_notes, 'Notes', maxLines: 5),
              ],
            ),
            const SizedBox(height: 12),
            _Section(
              title: 'Planning et devis',
              icon: Icons.event_note_outlined,
              children: [
                const SizedBox(height: 4),
                SegmentedButton<JobStatus>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                        value: JobStatus.attente, label: Text('En attente')),
                    ButtonSegment(
                        value: JobStatus.enCours, label: Text('En cours')),
                    ButtonSegment(
                        value: JobStatus.termine, label: Text('Terminé')),
                  ],
                  selected: {_status},
                  onSelectionChanged: (s) => setState(() => _status = s.first),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.event, color: cs.primary),
                  title: Text(_planned == null
                      ? 'Date prévue : non définie'
                      : _dateLong(_planned!)),
                  subtitle: const Text('Touchez pour choisir une date'),
                  trailing: _planned == null
                      ? null
                      : IconButton(
                          tooltip: 'Effacer la date',
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() => _planned = null),
                        ),
                  onTap: _pickDate,
                ),
                _tf(_quote, 'Devis',
                    suffix: '€',
                    type: const TextInputType.numberWithOptions(decimal: true),
                    formatters: _decimalOnly),
              ],
            ),
            if (isNew) ...[
              const SizedBox(height: 12),
              Text(
                'Vous pourrez ajouter les photos juste après l’enregistrement.',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: Text(isNew ? 'Enregistrer la fiche' : 'Enregistrer'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════ Onglet Stock ═════════════════════════

Color _stateColor(ColorScheme cs, String state) =>
    state == 'ok' ? cs.primary : (state == 'bas' ? cs.tertiary : cs.error);

String _stateLabel(String state) =>
    state == 'ok' ? 'OK' : (state == 'bas' ? 'Stock bas' : 'Rupture');

class _StockTab extends StatelessWidget {
  const _StockTab({required this.store});
  final AtelierStore store;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final items = store.stock;

    if (items.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          Card.filled(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 48, color: cs.primary),
                  const SizedBox(height: 12),
                  Text(
                    'Votre stock de consommables est vide.',
                    textAlign: TextAlign.center,
                    style: tt.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ajoutez les articles courants (papier à poncer, diluant, rubans de masquage…) puis réglez les quantités avec + et −.',
                    textAlign: TextAlign.center,
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: store.addDefaultStock,
                    icon: const Icon(Icons.playlist_add),
                    label: const Text('Ajouter les consommables courants'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final ok = items.where((s) => s.state == 'ok').length;
    final low = items.where((s) => s.state == 'bas').length;
    final out = items.where((s) => s.state == 'rupture').length;
    final toBuy = items.where((s) => s.state != 'ok').toList()
      ..sort((a, b) {
        if (a.state != b.state) return a.state == 'rupture' ? -1 : 1;
        return a.name.compareTo(b.name);
      });

    Widget legend(Color c, String label, int n) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text('$label : $n', style: tt.bodyMedium),
          ],
        );

    final List<Widget> groups = [];
    for (final cat in _stockCategories) {
      final list = items.where((s) => s.category == cat).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      if (list.isEmpty) continue;
      groups.add(Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text('$cat (${list.length})',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      ));
      for (final s in list) {
        groups.add(Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _StockCard(store: store, item: s),
        ));
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        Card.filled(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Vue d’ensemble', style: tt.titleLarge),
                const SizedBox(height: 4),
                Text('${items.length} article${items.length > 1 ? 's' : ''} suivis',
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 16,
                    child: Row(
                      children: [
                        if (ok > 0)
                          Expanded(
                              flex: ok,
                              child: Container(color: cs.primary)),
                        if (low > 0)
                          Expanded(
                              flex: low,
                              child: Container(color: cs.tertiary)),
                        if (out > 0)
                          Expanded(
                              flex: out,
                              child: Container(color: cs.error)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    legend(cs.primary, 'OK', ok),
                    legend(cs.tertiary, 'Bas', low),
                    legend(cs.error, 'Rupture', out),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (toBuy.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            color: cs.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.shopping_cart_outlined,
                          color: cs.onErrorContainer),
                      const SizedBox(width: 8),
                      Text('À racheter',
                          style: tt.titleMedium?.copyWith(
                              color: cs.onErrorContainer,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final s in toBuy)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(s.name,
                                style: tt.bodyLarge
                                    ?.copyWith(color: cs.onErrorContainer)),
                          ),
                          Text(
                            s.state == 'rupture'
                                ? 'Rupture'
                                : '${_fmtQty(s.qty)} ${s.unit}',
                            style: tt.bodyLarge?.copyWith(
                                color: cs.onErrorContainer,
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        ...groups,
      ],
    );
  }
}

class _StockCard extends StatelessWidget {
  const _StockCard({required this.store, required this.item});
  final AtelierStore store;
  final StockItem item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = _stateColor(cs, item.state);
    final step = _stepFor(item.unit);
    return Card.filled(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => _sheet(context, StockForm(store: store, item: item)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(item.name,
                        style: tt.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(_stateLabel(item.state),
                        style: tt.labelMedium?.copyWith(
                            color: item.state == 'ok'
                                ? cs.onPrimary
                                : (item.state == 'bas'
                                    ? cs.onTertiary
                                    : cs.onError),
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: item.fraction,
                  minHeight: 10,
                  color: color,
                  backgroundColor: cs.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('${_fmtQty(item.qty)} ${item.unit}',
                      style: tt.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton.filledTonal(
                    tooltip: 'Retirer ${_fmtQty(step)} ${item.unit}',
                    onPressed: () => store.adjustStock(item, -step),
                    icon: const Icon(Icons.remove),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    tooltip: 'Ajouter ${_fmtQty(step)} ${item.unit}',
                    onPressed: () => store.adjustStock(item, step),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StockForm extends StatefulWidget {
  const StockForm({super.key, required this.store, this.item});
  final AtelierStore store;
  final StockItem? item;

  @override
  State<StockForm> createState() => _StockFormState();
}

class _StockFormState extends State<StockForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _qty;
  late final TextEditingController _min;
  late final TextEditingController _full;
  late final TextEditingController _note;
  late String _category;
  late String _unit;

  @override
  void initState() {
    super.initState();
    final s = widget.item;
    _name = TextEditingController(text: s?.name ?? '');
    _qty = TextEditingController(text: _num(s?.qty ?? 0));
    _min = TextEditingController(text: _num(s?.minQty ?? 0));
    _full = TextEditingController(text: _num(s?.fullQty ?? 0));
    _note = TextEditingController(text: s?.note ?? '');
    _category = s?.category ?? _stockCategories.first;
    _unit = s?.unit ?? _stockUnits.first;
  }

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    _min.dispose();
    _full.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final s = widget.item;
    if (s == null) {
      widget.store.addStock(StockItem(
        id: _newId(),
        name: _name.text.trim(),
        category: _category,
        qty: _parse(_qty.text),
        unit: _unit,
        minQty: _parse(_min.text),
        fullQty: _parse(_full.text),
        note: _note.text.trim(),
      ));
    } else {
      s.name = _name.text.trim();
      s.category = _category;
      s.qty = _parse(_qty.text);
      s.unit = _unit;
      s.minQty = _parse(_min.text);
      s.fullQty = _parse(_full.text);
      s.note = _note.text.trim();
      widget.store.updateStock(s);
    }
    Navigator.pop(context);
  }

  Widget _dropdown(String label, String value, List<String> options,
      void Function(String) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isExpanded: true,
            value: value,
            items: [
              for (final o in options)
                DropdownMenuItem<String>(value: o, child: Text(o)),
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isNew = widget.item == null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(isNew ? 'Nouvel article' : 'Modifier l’article',
                  style: tt.titleLarge),
              _tf(_name, 'Nom (ex. Papier à poncer P400)',
                  autofocus: isNew,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Saisissez un nom'
                      : null),
              _dropdown('Catégorie', _category, _stockCategories,
                  (v) => setState(() => _category = v)),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _tf(_qty, 'Quantité en stock',
                        type: const TextInputType.numberWithOptions(
                            decimal: true),
                        formatters: _decimalOnly),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _dropdown('Unité', _unit, _stockUnits,
                        (v) => setState(() => _unit = v)),
                  ),
                ],
              ),
              _tf(_min, 'Alerte quand il en reste moins de',
                  type: const TextInputType.numberWithOptions(decimal: true),
                  formatters: _decimalOnly),
              _tf(_full, 'Stock plein (facultatif, pour la barre)',
                  type: const TextInputType.numberWithOptions(decimal: true),
                  formatters: _decimalOnly),
              _tf(_note, 'Note (marque, fournisseur…)', maxLines: 2),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                child: Text(isNew ? 'Ajouter' : 'Enregistrer'),
              ),
              if (!isNew) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () async {
                    final ok = await _confirm(
                      context,
                      title: 'Supprimer cet article ?',
                      message: '« ${widget.item!.name} » sera retiré du stock.',
                    );
                    if (ok) {
                      widget.store.deleteStock(widget.item!);
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Supprimer l’article'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════ Réglages ═════════════════════════

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.store});
  final AtelierStore store;

  Widget _title(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Réglages')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            _title(context, 'APPARENCE'),
            SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
                ButtonSegment(value: ThemeMode.light, label: Text('Clair')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Sombre')),
              ],
              selected: {store.themeMode},
              onSelectionChanged: (s) => store.setTheme(s.first),
            ),
            _title(context, 'SAUVEGARDE'),
            Card.filled(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.copy_all_outlined),
                    title: const Text('Copier ma sauvegarde'),
                    subtitle: const Text(
                        'Dossiers, fiches, formules et stock sous forme de texte'),
                    onTap: () async {
                      await Clipboard.setData(
                          ClipboardData(text: store.exportBackup()));
                      if (context.mounted) {
                        _snack(context,
                            'Sauvegarde copiée. Collez-la dans vos notes ou un message à vous-même.');
                      }
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.restore_outlined),
                    title: const Text('Restaurer une sauvegarde'),
                    subtitle: const Text('Remplace les données actuelles'),
                    onTap: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (_) => _RestoreDialog(store: store),
                      );
                      if (ok == true && context.mounted) {
                        _snack(context, 'Données restaurées');
                      }
                    },
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Text(
                'Les photos ne sont pas incluses dans la sauvegarde texte : elles restent enregistrées dans l’application, sur ce téléphone. Si vous la désinstallez, elles sont perdues.',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            _title(context, 'À PROPOS'),
            Card.filled(
              child: ListTile(
                leading: const Icon(Icons.format_paint_outlined),
                title: const Text(kAppName),
                subtitle: Text(kCreatorName.isEmpty
                    ? 'Version $kVersion'
                    : 'Version $kVersion · créé par $kCreatorName'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
              child: Text(
                'Toutes vos données restent sur ce téléphone. Aucune connexion Internet n’est utilisée.',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RestoreDialog extends StatefulWidget {
  const _RestoreDialog({required this.store});
  final AtelierStore store;

  @override
  State<_RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends State<_RestoreDialog> {
  final _c = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      setState(() {
        _c.text = data!.text!;
        _error = null;
      });
    }
  }

  Future<void> _restore() async {
    final text = _c.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Collez d’abord votre sauvegarde');
      return;
    }
    final ok = await _confirm(
      context,
      title: 'Remplacer les données ?',
      message:
          'Vos dossiers, fiches et stock actuels seront remplacés par la sauvegarde. Les photos ne sont pas restaurées.',
      action: 'Restaurer',
    );
    if (!ok || !mounted) return;
    if (widget.store.importBackup(text)) {
      Navigator.pop(context, true);
    } else {
      setState(() => _error = 'Sauvegarde invalide ou incomplète');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Restaurer une sauvegarde'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Collez ici le texte de votre sauvegarde.'),
            const SizedBox(height: 12),
            TextField(
              controller: _c,
              minLines: 4,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: '{"app":"atelier",…',
                errorText: _error,
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _paste,
              icon: const Icon(Icons.paste),
              label: const Text('Coller depuis le presse-papiers'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler')),
        FilledButton(onPressed: _restore, child: const Text('Restaurer')),
      ],
    );
  }
}
