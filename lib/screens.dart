import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import 'api.dart';
import 'app.dart';
import 'models.dart';

ApiClient apiOf(BuildContext context) => context.read<AppState>().api;

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

enum _AuthMode { login, register, forgot, reset }

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _resetCode = TextEditingController();
  _AuthMode _mode = _AuthMode.login;
  bool _busy = false;
  bool _obscure = true;
  String? _message;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _resetCode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final app = context.read<AppState>();
      switch (_mode) {
        case _AuthMode.login:
          await app.login(_email.text.trim(), _password.text);
        case _AuthMode.register:
          await app.register({
            'name': _name.text.trim(),
            'email': _email.text.trim(),
            'password': _password.text,
            'role': 'student',
          });
        case _AuthMode.forgot:
          await app.api.forgotPassword(_email.text.trim());
          if (mounted) {
            setState(() {
              _mode = _AuthMode.reset;
              _message = 'If that account exists, a reset code has been sent.';
            });
          }
        case _AuthMode.reset:
          await app.api.resetPassword(
            _email.text.trim(),
            _resetCode.text.trim(),
            _password.text,
          );
          if (mounted) {
            setState(() {
              _mode = _AuthMode.login;
              _message = 'Password updated. Sign in with your new password.';
            });
          }
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _configureApi() async {
    final api = context.read<AppState>().api;
    final controller = TextEditingController(text: api.baseUrl);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('API connection'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'API base URL',
            hintText: 'http://10.0.2.2:3000/api',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    try {
      await api.setBaseUrl(value);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('API base URL saved.')));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = error.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRegister = _mode == _AuthMode.register;
    final title = switch (_mode) {
      _AuthMode.login => 'Welcome back',
      _AuthMode.register => 'Create student account',
      _AuthMode.forgot => 'Reset your password',
      _AuthMode.reset => 'Choose a new password',
    };
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(
                          Icons.account_balance_outlined,
                          size: 48,
                          color: Color(0xff244c91),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'College Document Request & Management',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _configureApi,
                            icon: const Icon(Icons.settings_ethernet, size: 18),
                            label: const Text('API connection'),
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (isRegister)
                          TextFormField(
                            controller: _name,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Full name',
                            ),
                            validator: (v) => (v ?? '').trim().isEmpty
                                ? 'Enter your name'
                                : null,
                          ),
                        if (isRegister) const SizedBox(height: 12),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(labelText: 'Email'),
                          validator: (v) => (v ?? '').contains('@')
                              ? null
                              : 'Enter a valid email address',
                        ),
                        if (_mode == _AuthMode.reset ||
                            _mode == _AuthMode.login ||
                            isRegister) ...[
                          const SizedBox(height: 12),
                          if (_mode == _AuthMode.reset)
                            TextFormField(
                              controller: _resetCode,
                              decoration: const InputDecoration(
                                labelText: 'Reset code',
                              ),
                              validator: (v) => (v ?? '').isEmpty
                                  ? 'Enter your reset code'
                                  : null,
                            ),
                          if (_mode == _AuthMode.reset)
                            const SizedBox(height: 12),
                          TextFormField(
                            controller: _password,
                            obscureText: _obscure,
                            decoration: InputDecoration(
                              labelText: _mode == _AuthMode.reset
                                  ? 'New password'
                                  : 'Password',
                              suffixIcon: IconButton(
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            validator: (v) => (v ?? '').length < 8
                                ? 'Use at least 8 characters'
                                : null,
                          ),
                        ],
                        if (_message != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _message!,
                            style: TextStyle(
                              color:
                                  _message!.startsWith('If that') ||
                                      _message!.startsWith('Password updated')
                                  ? Colors.green.shade800
                                  : Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(switch (_mode) {
                                  _AuthMode.login => 'Sign in',
                                  _AuthMode.register => 'Create account',
                                  _AuthMode.forgot => 'Send reset code',
                                  _AuthMode.reset => 'Update password',
                                }),
                        ),
                        if (_mode == _AuthMode.login) ...[
                          TextButton(
                            onPressed: () => setState(() {
                              _mode = _AuthMode.forgot;
                              _message = null;
                            }),
                            child: const Text('Forgot password?'),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              _mode = _AuthMode.register;
                              _message = null;
                            }),
                            child: const Text('Create a student account'),
                          ),
                        ] else
                          TextButton(
                            onPressed: () => setState(() {
                              _mode = _AuthMode.login;
                              _message = null;
                            }),
                            child: const Text('Back to sign in'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RoleHome extends StatefulWidget {
  const RoleHome({required this.user, super.key});
  final AppUser user;

  @override
  State<RoleHome> createState() => _RoleHomeState();
}

class _RoleHomeState extends State<RoleHome> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final role = widget.user.role;
    final pages = switch (role) {
      UserRole.student => <Widget>[
        StudentHome(user: widget.user),
        const NotificationsScreen(),
        ProfileScreen(user: widget.user),
      ],
      UserRole.coordinator => <Widget>[
        const CoordinatorHome(),
        const NotificationsScreen(),
        ProfileScreen(user: widget.user),
      ],
      UserRole.authority => <Widget>[
        const AuthorityHome(),
        const NotificationsScreen(),
        ProfileScreen(user: widget.user),
      ],
      UserRole.admin => <Widget>[
        const AdminHome(),
        const NotificationsScreen(),
        ProfileScreen(user: widget.user),
      ],
    };
    final labels = switch (role) {
      UserRole.student => ['Requests', 'Alerts', 'Profile'],
      UserRole.coordinator => ['Review queue', 'Alerts', 'Profile'],
      UserRole.authority => ['Signing tasks', 'Alerts', 'Profile'],
      UserRole.admin => ['Users', 'Alerts', 'Profile'],
    };
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          NavigationDestination(icon: Icon(_homeIcon(role)), label: labels[0]),
          NavigationDestination(
            icon: const Icon(Icons.notifications_outlined),
            label: labels[1],
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            label: labels[2],
          ),
        ],
      ),
    );
  }

  IconData _homeIcon(UserRole role) => switch (role) {
    UserRole.student => Icons.description_outlined,
    UserRole.coordinator => Icons.fact_check_outlined,
    UserRole.authority => Icons.draw_outlined,
    UserRole.admin => Icons.people_outline,
  };
}

class PageTitle extends StatelessWidget {
  const PageTitle(
    this.title, {
    this.subtitle,
    this.actions = const [],
    super.key,
  });
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ],
          ),
        ),
        ...actions,
      ],
    ),
  );
}

class AsyncPanel<T> extends StatelessWidget {
  const AsyncPanel({
    required this.future,
    required this.builder,
    this.onRetry,
    super.key,
  });
  final Future<T> future;
  final Widget Function(BuildContext context, T value) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(36),
            child: CircularProgressIndicator(),
          ),
        );
      }
      if (snapshot.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 40),
                const SizedBox(height: 12),
                Text(snapshot.error.toString(), textAlign: TextAlign.center),
                if (onRetry != null)
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
              ],
            ),
          ),
        );
      }
      return builder(context, snapshot.data as T);
    },
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.message, {this.icon = Icons.inbox_outlined, super.key});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: Colors.blueGrey),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

class StatusChip extends StatelessWidget {
  const StatusChip({required this.status, super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final key = normalizedStatus(status);
    final color = key.contains('reject') || key.contains('return')
        ? Colors.deepOrange
        : key.contains('publish') || key.contains('complete')
        ? Colors.green
        : key.contains('correction') || key.contains('information')
        ? Colors.orange
        : Theme.of(context).colorScheme.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          prettyStatus(status),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class StudentHome extends StatefulWidget {
  const StudentHome({required this.user, super.key});
  final AppUser user;

  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<StudentHome> {
  late Future<List<dynamic>> _future;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _future = apiOf(context).myRequests();

  Future<void> _newRequest() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NewRequestScreen()),
    );
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        PageTitle(
          'My requests',
          subtitle: 'Hello, ${widget.user.name}',
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: () => setState(_reload),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        Expanded(
          child: AsyncPanel<List<dynamic>>(
            future: _future,
            onRetry: () => setState(_reload),
            builder: (context, values) {
              final requests = values
                  .map((e) => DocumentRequest.fromJson(asJson(e)))
                  .toList();
              if (requests.isEmpty) {
                return const EmptyState(
                  'No document requests yet. Start a new request.',
                );
              }
              return RefreshIndicator(
                onRefresh: () async => setState(_reload),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  children: [
                    for (final request in requests)
                      RequestCard(
                        request: request,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                RequestDetailScreen(request: request),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _newRequest,
              icon: const Icon(Icons.add),
              label: const Text('Request a document'),
            ),
          ),
        ),
      ],
    ),
  );
}

class RequestCard extends StatelessWidget {
  const RequestCard({required this.request, required this.onTap, super.key});
  final DocumentRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: ListTile(
      contentPadding: const EdgeInsets.all(16),
      title: Text(
        request.title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusChip(status: request.status),
            if (request.createdAt.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(request.createdAt),
            ],
          ],
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

class NewRequestScreen extends StatefulWidget {
  const NewRequestScreen({super.key});

  @override
  State<NewRequestScreen> createState() => _NewRequestScreenState();
}

class _NewRequestScreenState extends State<NewRequestScreen> {
  late Future<List<dynamic>> _typesFuture;
  final _formKey = GlobalKey<FormState>();
  final Map<String, dynamic> _values = {};
  List<UploadFile> _files = [];
  DocumentType? _selected;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _typesFuture = apiOf(context).documentTypes();
  }

  Future<void> _selectFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (result == null) return;
    setState(() {
      _files = result.files
          .map(
            (file) =>
                UploadFile(name: file.name, path: file.path, bytes: file.bytes),
          )
          .toList();
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _selected == null) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await apiOf(context).createRequest(
        documentTypeId: _selected!.id,
        fields: Map<String, dynamic>.from(_values),
        supportingFiles: _files,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _dynamicField(JsonMap field) {
    final name = textOf(
      field['name'] ??
          field['key'] ??
          field['fieldKey'] ??
          field['fieldName'] ??
          field['id'] ??
          field['label'],
      'field',
    );
    final label = textOf(
      field['label'] ?? field['title'] ?? field['fieldName'] ?? name,
    );
    final type = textOf(
      field['type'] ?? field['inputType'] ?? field['fieldType'],
      'text',
    ).toLowerCase();
    final required =
        field['required'] == true ||
        field['isRequired'] == true ||
        field['mandatory'] == true;
    final options = field['options'] is List
        ? (field['options'] as List)
              .map(
                (item) => item is Map
                    ? textOf(asJson(item)['value'] ?? asJson(item)['label'])
                    : textOf(item),
              )
              .where((item) => item.isNotEmpty)
              .toList()
        : <String>[];
    if (type == 'select' || type == 'dropdown' || options.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          initialValue: options.contains(_values[name])
              ? _values[name] as String?
              : null,
          decoration: InputDecoration(labelText: label),
          items: options
              .map(
                (option) =>
                    DropdownMenuItem(value: option, child: Text(option)),
              )
              .toList(),
          onChanged: (value) => _values[name] = value,
          validator: required
              ? (value) => value == null ? 'Choose $label' : null
              : null,
        ),
      );
    }
    final keyboard = type == 'number' || type == 'numeric'
        ? const TextInputType.numberWithOptions(decimal: true)
        : type == 'email'
        ? TextInputType.emailAddress
        : type == 'date'
        ? TextInputType.datetime
        : TextInputType.text;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        initialValue: _values[name]?.toString(),
        keyboardType: keyboard,
        maxLines: type == 'textarea' || type == 'longtext' ? 3 : 1,
        decoration: InputDecoration(
          labelText: label,
          helperText: textOf(field['helpText'] ?? field['description']).isEmpty
              ? null
              : textOf(field['helpText'] ?? field['description']),
        ),
        validator: (value) {
          if (required && (value ?? '').trim().isEmpty) return 'Enter $label';
          if (type == 'email' &&
              (value ?? '').isNotEmpty &&
              !(value ?? '').contains('@')) {
            return 'Enter a valid email';
          }
          return null;
        },
        onChanged: (value) => _values[name] = value,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('New document request')),
    body: AsyncPanel<List<dynamic>>(
      future: _typesFuture,
      onRetry: () =>
          setState(() => _typesFuture = apiOf(context).documentTypes()),
      builder: (context, rawTypes) {
        final types = rawTypes
            .map((e) => DocumentType.fromJson(asJson(e)))
            .toList();
        if (types.isEmpty) {
          return const EmptyState(
            'No document types are configured. Please contact your college office.',
          );
        }
        return Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Select document type',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: types.any((type) => type.id == _selected?.id)
                    ? _selected!.id
                    : null,
                decoration: const InputDecoration(labelText: 'Document type'),
                items: types
                    .map(
                      (type) => DropdownMenuItem(
                        value: type.id,
                        child: Text(type.name),
                      ),
                    )
                    .toList(),
                onChanged: (id) => setState(() {
                  _selected = id == null
                      ? null
                      : types.firstWhere((type) => type.id == id);
                  _values.clear();
                }),
                validator: (value) =>
                    value == null ? 'Select a document type' : null,
              ),
              if (_selected?.description.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text(_selected!.description),
              ],
              if (_selected != null) ...[
                const SizedBox(height: 20),
                Text(
                  'Request details',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                for (final field in _selected!.fields) _dynamicField(field),
              ],
              const SizedBox(height: 12),
              Text(
                'Supporting files',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _selectFiles,
                icon: const Icon(Icons.attach_file),
                label: Text(
                  _files.isEmpty
                      ? 'Choose files'
                      : 'Choose files (${_files.length} selected)',
                ),
              ),
              for (final file in _files)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.insert_drive_file_outlined),
                  title: Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    onPressed: () => setState(() => _files.remove(file)),
                    icon: const Icon(Icons.close),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Submit request'),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class RequestDetailScreen extends StatefulWidget {
  const RequestDetailScreen({required this.request, super.key});
  final DocumentRequest request;

  @override
  State<RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends State<RequestDetailScreen> {
  late Future<List<dynamic>> _details;
  final _correction = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _correction.dispose();
    super.dispose();
  }

  void _reload() {
    final api = apiOf(context);
    _details = Future.wait([
      api.requestProgress(widget.request.id),
      api.requestHistory(widget.request.id),
    ]);
  }

  Future<void> _sendCorrection() async {
    if (_correction.text.trim().isEmpty) {
      setState(() => _error = 'Add a response before submitting.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await apiOf(context).action(widget.request.id, 'submit-correction', {
        'message': _correction.text.trim(),
      });
      if (mounted) {
        setState(() {
          _correction.clear();
          _reload();
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _cancelRequest() async {
    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this request?'),
        content: const Text('The document request will stop progressing.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep request'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );
    if (shouldCancel != true) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await apiOf(context).action(widget.request.id, 'cancel');
      if (mounted) setState(_reload);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _download(JsonMap progress) async {
    final id = fileVersionId(progress);
    if (id.isEmpty) {
      setState(
        () => _error = 'There is no published document available to download.',
      );
      return;
    }
    await downloadAndOpen(
      context,
      id,
      suggestedName: '${widget.request.title}.pdf',
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Request details')),
    body: AsyncPanel<List<dynamic>>(
      future: _details,
      onRetry: () => setState(_reload),
      builder: (context, data) {
        final progress = asJson(unwrap(data[0]));
        final history = asList(data[1]);
        final currentStatus = textOf(
          progress['currentStatus'] ??
              progress['status'] ??
              asJson(progress['request'])['status'] ??
              widget.request.status,
        );
        final request = asJson(progress['request']);
        final needsResponse =
            normalizedStatus(currentStatus).contains('correction') ||
            normalizedStatus(currentStatus).contains('information');
        final canCancel =
            progressIndexForStatus(currentStatus) <= 1 &&
            !isTerminalStatus(currentStatus) &&
            !normalizedStatus(currentStatus).contains('publish');
        final hasPublished =
            fileVersionId(progress).isNotEmpty ||
            normalizedStatus(currentStatus).contains('publish');
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.request.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    StatusChip(status: currentStatus),
                    if (widget.request.description.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(widget.request.description),
                    ],
                  ],
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Progress',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    RequestTimeline(status: currentStatus, history: history),
                  ],
                ),
              ),
            ),
            if (needsResponse) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Response requested',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        textOf(
                          progress['informationRequested'] ??
                              progress['correctionReason'] ??
                              progress['message'] ??
                              progress['reason'] ??
                              request['coordinatorMessage'],
                          'Please provide the requested information or correction.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _correction,
                        minLines: 2,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Your response',
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: _submitting ? null : _sendCorrection,
                        child: const Text('Submit response'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (hasPublished)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final id = fileVersionId(progress);
                        if (id.isEmpty) {
                          setState(
                            () => _error =
                                'There is no published document available to preview.',
                          );
                          return;
                        }
                        await downloadAndOpen(
                          context,
                          id,
                          preview: true,
                          suggestedName: '${widget.request.title}.pdf',
                        );
                      },
                      icon: const Icon(Icons.preview_outlined),
                      label: const Text('Preview'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _download(progress),
                      icon: const Icon(Icons.download),
                      label: const Text('Download'),
                    ),
                  ),
                ],
              ),
            if (canCancel)
              TextButton.icon(
                onPressed: _submitting ? null : _cancelRequest,
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancel request'),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class RequestTimeline extends StatelessWidget {
  const RequestTimeline({
    required this.status,
    required this.history,
    super.key,
  });
  final String status;
  final List<dynamic> history;

  @override
  Widget build(BuildContext context) {
    final current = progressIndexForStatus(status);
    final rejected = isTerminalStatus(status);
    final entries = history.map((raw) => asJson(raw)).where((item) {
      return textOf(
        item['status'] ?? item['action'] ?? item['event'],
      ).isNotEmpty;
    }).toList();
    return Column(
      children: [
        for (var i = 0; i < requestProgressStages.length; i++)
          _TimelineRow(
            title: requestProgressStages[i],
            done: !rejected && i < current,
            active: !rejected && i == current,
            last: i == requestProgressStages.length - 1,
          ),
        if (rejected)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.cancel_outlined,
              color: Colors.deepOrange,
            ),
            title: Text(prettyStatus(status)),
            subtitle: const Text('This request is no longer progressing.'),
          ),
        if (entries.isNotEmpty) ...[
          const Divider(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Activity history',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          const SizedBox(height: 8),
          for (final entry in entries.reversed)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history, size: 18),
              title: Text(
                prettyStatus(
                  textOf(entry['status'] ?? entry['action'] ?? entry['event']),
                ),
              ),
              subtitle: Text(
                textOf(
                  entry['createdAt'] ?? entry['timestamp'] ?? entry['date'],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.title,
    required this.done,
    required this.active,
    required this.last,
  });
  final String title;
  final bool done;
  final bool active;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final color = done || active
        ? Theme.of(context).colorScheme.primary
        : Colors.blueGrey.shade200;
    return IntrinsicHeight(
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Icon(
                  done ? Icons.check_circle : Icons.circle,
                  size: active ? 19 : 15,
                  color: color,
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: done ? color : Colors.blueGrey.shade100,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16, top: 1),
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                  color: active || done ? null : Colors.blueGrey,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String fileVersionId(JsonMap value) {
  final request = asJson(value['request']);
  final candidates = [
    value['publishedVersionId'],
    value['versionId'],
    value['currentVersionId'],
    value['documentVersionId'],
    value['publishedVersion'],
    value['currentVersion'],
    value['documentVersion'],
    value['publishedDocument'],
    value['currentVersion'],
    value['currentDocument'],
    value['document'],
    value['latestDocument'],
    request['finalVersion'],
    request['currentVersion'],
  ];
  for (final candidate in candidates) {
    final id = candidate is Map
        ? textOf(
            asJson(candidate)['versionId'] ??
                asJson(candidate)['documentVersionId'] ??
                asJson(candidate)['id'] ??
                asJson(candidate)['_id'],
          )
        : textOf(candidate);
    if (id.isNotEmpty) return id;
  }
  return '';
}

Future<void> downloadAndOpen(
  BuildContext context,
  String versionId, {
  bool preview = false,
  String? suggestedName,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final file = await apiOf(
      context,
    ).downloadFile(versionId, preview: preview, suggestedName: suggestedName);
    await OpenFilex.open(file.path);
  } catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(error.toString())));
  }
}

class CoordinatorHome extends StatefulWidget {
  const CoordinatorHome({super.key});

  @override
  State<CoordinatorHome> createState() => _CoordinatorHomeState();
}

class _CoordinatorHomeState extends State<CoordinatorHome> {
  late Future<List<dynamic>> _data;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _data = Future.wait([
    apiOf(context).coordinatorRequests(),
    apiOf(context).coordinatorStats(),
  ]);

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        PageTitle(
          'Review queue',
          subtitle: 'Review requests and manage document workflows',
          actions: [
            IconButton(
              onPressed: () => setState(_reload),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        Expanded(
          child: AsyncPanel<List<dynamic>>(
            future: _data,
            onRetry: () => setState(_reload),
            builder: (context, result) {
              final requests = asList(
                result[0],
              ).map((e) => DocumentRequest.fromJson(asJson(e))).toList();
              final stats = asJson(unwrap(result[1]));
              return RefreshIndicator(
                onRefresh: () async => setState(_reload),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    _StatsStrip(stats: stats),
                    const SizedBox(height: 16),
                    Text(
                      'Requests (${requests.length})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (requests.isEmpty)
                      const EmptyState(
                        'The review queue is clear.',
                        icon: Icons.task_alt_outlined,
                      )
                    else
                      for (final request in requests)
                        RequestCard(
                          request: request,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    CoordinatorRequestScreen(request: request),
                              ),
                            );
                            if (mounted) setState(_reload);
                          },
                        ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({required this.stats});
  final JsonMap stats;

  @override
  Widget build(BuildContext context) {
    int countFor(List<String> statuses) => statuses.fold<int>(
      0,
      (total, status) => total + (int.tryParse(textOf(stats[status])) ?? 0),
    );
    final values = <(String, String, IconData)>[
      (
        'Pending',
        textOf(
          stats['pending'] ??
              stats['pendingRequests'] ??
              stats['pendingCount'] ??
              countFor(['submitted', 'information_requested']),
        ),
        Icons.hourglass_top,
      ),
      (
        'In progress',
        textOf(
          stats['inProgress'] ??
              stats['inProgressRequests'] ??
              stats['active'] ??
              countFor([
                'accepted',
                'prepared',
                'in_workflow',
                'correction_requested',
                'final_verification',
              ]),
        ),
        Icons.sync,
      ),
      (
        'Published',
        textOf(
          stats['published'] ??
              stats['publishedRequests'] ??
              stats['completed'],
          '—',
        ),
        Icons.task_alt,
      ),
    ];
    return Row(
      children: [
        for (final item in values)
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 8,
                ),
                child: Column(
                  children: [
                    Icon(item.$3, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 7),
                    Text(
                      item.$2,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      item.$1,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class CoordinatorRequestScreen extends StatefulWidget {
  const CoordinatorRequestScreen({required this.request, super.key});
  final DocumentRequest request;

  @override
  State<CoordinatorRequestScreen> createState() =>
      _CoordinatorRequestScreenState();
}

class _CoordinatorRequestScreenState extends State<CoordinatorRequestScreen> {
  bool _busy = false;
  String? _error;
  String? _workflowError;
  List<WorkflowOption> _workflows = [];
  String? _selectedWorkflow;
  List<JsonMap> _templates = [];
  String? _selectedTemplate;
  UploadFile? _document;
  late String _status;
  late bool _finalVerified;

  @override
  void initState() {
    super.initState();
    _status = widget.request.status;
    _finalVerified = widget.request.json['finalVerifiedAt'] != null;
    _loadWorkflows();
  }

  Future<void> _loadWorkflows() async {
    try {
      final api = apiOf(context);
      final raw = asJson(unwrap(await api.coordinatorStats()));
      final list =
          raw['signingWorkflows'] ??
          raw['workflows'] ??
          raw['signing_workflows'];
      if (list is List && mounted) {
        setState(() {
          _workflows = list
              .map((item) {
                final map = asJson(item);
                return WorkflowOption(
                  textOf(map['id'] ?? map['_id'] ?? map['workflowId']),
                  textOf(
                    map['name'] ?? map['label'] ?? map['title'],
                    'Signing workflow',
                  ),
                );
              })
              .where((workflow) => workflow.id.isNotEmpty)
              .toList();
        });
      }
      final rawType = widget.request.json['documentType'];
      final typeId = rawType is Map
          ? textOf(asJson(rawType)['id'] ?? asJson(rawType)['_id'])
          : textOf(rawType);
      final templates = await api.templates(documentTypeId: typeId);
      if (mounted) {
        setState(() {
          _templates = templates.map((item) => asJson(item)).toList();
        });
      }
    } catch (error) {
      if (mounted) setState(() => _workflowError = error.toString());
    }
  }

  Future<void> _chooseDocument() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (result?.files.isNotEmpty != true) return;
    final file = result!.files.first;
    setState(
      () => _document = UploadFile(
        name: file.name,
        path: file.path,
        bytes: file.bytes,
      ),
    );
  }

  Future<String?> _ask(String title, String hint) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _run(String action, [JsonMap body = const {}]) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final raw = asJson(
        unwrap(await apiOf(context).action(widget.request.id, action, body)),
      );
      final request = raw['request'] is Map ? asJson(raw['request']) : raw;
      if (mounted) {
        setState(() {
          _status = textOf(request['status'], _status);
          if (action == 'verification/complete') _finalVerified = true;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Request updated.')));
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadDocument() async {
    if (_document == null) {
      await _chooseDocument();
      if (_document == null) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final raw = asJson(
        unwrap(
          await apiOf(context).uploadAction(
            widget.request.id,
            'prepare-upload',
            fileField: 'file',
            file: _document!,
          ),
        ),
      );
      final request = raw['request'] is Map ? asJson(raw['request']) : raw;
      if (mounted) {
        setState(() => _status = textOf(request['status'], _status));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document uploaded for this request.')),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generateFromTemplate() async {
    if (_selectedTemplate == null) {
      setState(() => _error = 'Select an approved template first.');
      return;
    }
    await _run('generate-document', {'templateId': _selectedTemplate});
  }

  Future<void> _startSignature() async {
    if (normalizedStatus(_status) != 'prepared') {
      setState(
        () => _error =
            'Upload a prepared PDF or generate one from a template first.',
      );
      return;
    }
    if (_selectedWorkflow == null || _selectedWorkflow!.isEmpty) {
      setState(() => _error = 'Select a configured signing workflow first.');
      return;
    }
    await _run('submit-for-signature', {'workflowId': _selectedWorkflow});
  }

  @override
  Widget build(BuildContext context) {
    final normalized = normalizedStatus(_status);
    final reviewStage =
        normalized.contains('pending') ||
        normalized.contains('submitted') ||
        normalized.contains('review');
    final verificationStage =
        normalized.contains('verif') || normalized == 'correctionrequested';
    return Scaffold(
      appBar: AppBar(title: const Text('Review request')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.request.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.request.studentName.isEmpty
                        ? widget.request.studentEmail
                        : '${widget.request.studentName} · ${widget.request.studentEmail}',
                  ),
                  const SizedBox(height: 12),
                  StatusChip(status: _status),
                  if (widget.request.description.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(widget.request.description),
                  ],
                ],
              ),
            ),
          ),
          if (reviewStage) ...[
            _ActionCard(
              title: 'Initial review',
              children: [
                _actionButton(
                  'Accept request',
                  Icons.check,
                  () => _run('accept'),
                ),
                _actionButton(
                  'Request information',
                  Icons.help_outline,
                  () async {
                    final reason = await _ask(
                      'Request information',
                      'What information is needed?',
                    );
                    if (reason?.isNotEmpty == true) {
                      await _run('request-information', {'message': reason});
                    }
                  },
                ),
                _actionButton('Reject request', Icons.block, () async {
                  final reason = await _ask(
                    'Reject request',
                    'Reason for rejection',
                  );
                  if (reason?.isNotEmpty == true) {
                    await _run('reject', {'reason': reason});
                  }
                }),
              ],
            ),
          ],
          _ActionCard(
            title: 'Prepare document',
            children: [
              if (_document != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined),
                  title: Text(_document!.name),
                  trailing: IconButton(
                    onPressed: () => setState(() => _document = null),
                    icon: const Icon(Icons.close),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _chooseDocument,
                icon: const Icon(Icons.upload_file),
                label: const Text('Choose prepared PDF'),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : _uploadDocument,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Upload prepared PDF'),
              ),
              const SizedBox(height: 8),
              if (_templates.isNotEmpty) ...[
                DropdownButtonFormField<String>(
                  initialValue:
                      _templates.any(
                        (template) =>
                            textOf(template['id'] ?? template['_id']) ==
                            _selectedTemplate,
                      )
                      ? _selectedTemplate
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Approved document template',
                  ),
                  items: _templates
                      .map(
                        (template) => DropdownMenuItem(
                          value: textOf(template['id'] ?? template['_id']),
                          child: Text(textOf(template['name'], 'Template')),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _selectedTemplate = value),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _generateFromTemplate,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('Generate from approved template'),
                ),
              ],
              if (_workflowError != null)
                Text(
                  _workflowError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_workflows.isEmpty)
                const Text(
                  'No signing workflows are configured for this account.',
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: _workflows.any((w) => w.id == _selectedWorkflow)
                      ? _selectedWorkflow
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Signing workflow',
                  ),
                  items: _workflows
                      .map(
                        (workflow) => DropdownMenuItem(
                          value: workflow.id,
                          child: Text(workflow.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _selectedWorkflow = value),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed:
                    _busy ||
                        _workflows.isEmpty ||
                        normalizedStatus(_status) != 'prepared'
                    ? null
                    : _startSignature,
                icon: const Icon(Icons.draw_outlined),
                label: const Text('Start signing workflow'),
              ),
              if (normalizedStatus(_status) != 'prepared')
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'First accept the request, then upload a prepared PDF or generate one from an approved template.',
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
          if (verificationStage)
            _ActionCard(
              title: normalized == 'correctionrequested'
                  ? 'Verify returned signature'
                  : 'Final verification',
              children: [
                if (normalized == 'correctionrequested') ...[
                  _actionButton(
                    'Accept and forward',
                    Icons.verified_outlined,
                    () => _run('verification/accept'),
                  ),
                  _actionButton('Return for correction', Icons.undo, () async {
                    final reason = await _ask(
                      'Return for correction',
                      'Describe the correction',
                    );
                    if (reason?.isNotEmpty == true) {
                      await _run('verification/return', {'message': reason});
                    }
                  }),
                ] else ...[
                  if (!_finalVerified)
                    _actionButton(
                      'Complete final verification',
                      Icons.verified_outlined,
                      () => _run('verification/complete'),
                    ),
                  if (_finalVerified)
                    _actionButton(
                      'Publish final document',
                      Icons.publish,
                      () => _run('publish'),
                    ),
                ],
              ],
            ),
          if (!reviewStage && !verificationStage)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Use the available actions below to prepare and route this request.',
                ),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _actionButton(String label, IconData icon, VoidCallback onPressed) =>
      OutlinedButton.icon(
        onPressed: _busy ? null : onPressed,
        icon: Icon(icon),
        label: Text(label),
      );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    ),
  );
}

class AuthorityHome extends StatefulWidget {
  const AuthorityHome({super.key});

  @override
  State<AuthorityHome> createState() => _AuthorityHomeState();
}

class _AuthorityHomeState extends State<AuthorityHome> {
  late Future<List<dynamic>> _tasks;
  int _tab = 0;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _tasks = apiOf(context).authorityTasks();

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        PageTitle(
          'Signing tasks',
          subtitle: 'Review and sign assigned college documents',
          actions: [
            IconButton(
              onPressed: () => setState(_reload),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('Pending')),
              ButtonSegment(value: 1, label: Text('Completed / history')),
            ],
            selected: {_tab},
            onSelectionChanged: (value) => setState(() => _tab = value.first),
          ),
        ),
        Expanded(
          child: AsyncPanel<List<dynamic>>(
            future: _tasks,
            onRetry: () => setState(_reload),
            builder: (context, values) {
              final tasks = values.map((e) => asJson(e)).toList();
              final filtered = tasks.where((task) {
                final done = _isTaskComplete(
                  textOf(task['status'] ?? task['state']),
                );
                return _tab == 1 ? done : !done;
              }).toList();
              if (filtered.isEmpty) {
                return EmptyState(
                  _tab == 0
                      ? 'No pending signing tasks.'
                      : 'No completed tasks yet.',
                  icon: _tab == 0
                      ? Icons.draw_outlined
                      : Icons.history_outlined,
                );
              }
              return RefreshIndicator(
                onRefresh: () async => setState(_reload),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    for (final task in filtered)
                      _TaskCard(
                        task: task,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AuthorityTaskScreen(task: task),
                            ),
                          );
                          if (mounted) setState(_reload);
                        },
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

bool _isTaskComplete(String status) {
  final value = normalizedStatus(status);
  return value.contains('complete') ||
      value.contains('signed') ||
      value.contains('verified') ||
      value.contains('published') ||
      value.contains('returned') ||
      value.contains('reject');
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.onTap});
  final JsonMap task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final request = asJson(task['request']);
    final id = textOf(task['id'] ?? task['_id'] ?? task['taskId']);
    final title = textOf(
      request['documentTypeName'] ??
          asJson(request['documentType'])['name'] ??
          task['title'] ??
          task['documentName'],
      'Signing task',
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(title),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusChip(
                status: textOf(task['status'] ?? task['state'], 'pending'),
              ),
              if (id.isNotEmpty) Text('Task $id'),
            ],
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class AuthorityTaskScreen extends StatefulWidget {
  const AuthorityTaskScreen({required this.task, super.key});
  final JsonMap task;

  @override
  State<AuthorityTaskScreen> createState() => _AuthorityTaskScreenState();
}

class _AuthorityTaskScreenState extends State<AuthorityTaskScreen> {
  late Future<dynamic> _detail;
  UploadFile? _signedFile;
  bool _busy = false;
  String? _error;

  String get _taskId =>
      textOf(widget.task['id'] ?? widget.task['_id'] ?? widget.task['taskId']);

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _detail = apiOf(context).authorityTask(_taskId);

  Future<void> _pickSignedFile() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (result?.files.isNotEmpty != true) return;
    final file = result!.files.first;
    setState(
      () => _signedFile = UploadFile(
        name: file.name,
        path: file.path,
        bytes: file.bytes,
      ),
    );
  }

  Future<void> _download(JsonMap task) async {
    final id = fileVersionId(task);
    if (id.isEmpty) {
      setState(() => _error = 'No current document is available to download.');
      return;
    }
    await downloadAndOpen(context, id, suggestedName: 'document.pdf');
  }

  Future<void> _upload() async {
    if (_signedFile == null) await _pickSignedFile();
    if (_signedFile == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await apiOf(context).uploadSignedDocument(_taskId, _signedFile!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Signed document uploaded.')),
        );
        setState(_reload);
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _returnForCorrection() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Return for correction'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Reason'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Return'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason?.isEmpty != false) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await apiOf(context).returnAuthorityTask(_taskId, reason!);
      if (mounted) setState(_reload);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Task details')),
    body: AsyncPanel<dynamic>(
      future: _detail,
      onRetry: () => setState(_reload),
      builder: (context, raw) {
        final response = asJson(unwrap(raw));
        final task = response['task'] is Map
            ? asJson(response['task'])
            : response;
        final request = asJson(task['request']);
        final isActiveTask =
            normalizedStatus(textOf(task['status'] ?? task['state'])) ==
            'active';
        final title = textOf(
          request['documentTypeName'] ??
              asJson(request['documentType'])['name'] ??
              task['title'] ??
              task['documentName'],
          'Signing task',
        );
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      textOf(
                        request['studentName'] ??
                            asJson(request['student'])['name'] ??
                            task['studentName'],
                        'Student',
                      ),
                    ),
                    const SizedBox(height: 10),
                    StatusChip(
                      status: textOf(
                        task['status'] ?? task['state'],
                        'pending',
                      ),
                    ),
                    if (textOf(
                      task['instructions'] ?? task['note'],
                    ).isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(textOf(task['instructions'] ?? task['note'])),
                    ],
                  ],
                ),
              ),
            ),
            if (!isActiveTask)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'This task is not currently active. You can review it after it is routed to you.',
                ),
              ),
            OutlinedButton.icon(
              onPressed: isActiveTask ? () => _download(task) : null,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download current document'),
            ),
            OutlinedButton.icon(
              onPressed: isActiveTask
                  ? () {
                      final id = fileVersionId(task);
                      if (id.isEmpty) {
                        setState(
                          () => _error =
                              'No current document is available to preview.',
                        );
                        return;
                      }
                      downloadAndOpen(
                        context,
                        id,
                        preview: true,
                        suggestedName: 'document-preview.pdf',
                      );
                    }
                  : null,
              icon: const Icon(Icons.preview_outlined),
              label: const Text('Preview current document'),
            ),
            if (_signedFile != null)
              ListTile(
                leading: const Icon(Icons.attach_file),
                title: Text(_signedFile!.name),
                trailing: IconButton(
                  onPressed: () => setState(() => _signedFile = null),
                  icon: const Icon(Icons.close),
                ),
              ),
            FilledButton.icon(
              onPressed: _busy || !isActiveTask ? null : _pickSignedFile,
              icon: const Icon(Icons.upload_file),
              label: const Text('Choose signed document'),
            ),
            FilledButton.icon(
              onPressed: _busy || !isActiveTask ? null : _upload,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: const Text('Upload signed document'),
            ),
            OutlinedButton.icon(
              onPressed: _busy || !isActiveTask ? null : _returnForCorrection,
              icon: const Icon(Icons.undo),
              label: const Text('Return for correction'),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_busy) const Center(child: CircularProgressIndicator()),
          ],
        );
      },
    ),
  );
}

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  late Future<List<dynamic>> _users;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _users = apiOf(context).users();

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        PageTitle(
          'User management',
          subtitle: 'Manage access and role assignments',
          actions: [
            IconButton(
              onPressed: () => setState(_reload),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        Expanded(
          child: AsyncPanel<List<dynamic>>(
            future: _users,
            onRetry: () => setState(_reload),
            builder: (context, raw) {
              final users = raw.map((item) => asJson(item)).toList();
              if (users.isEmpty) return const EmptyState('No users found.');
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: users.length,
                itemBuilder: (context, index) => _AdminUserCard(
                  user: users[index],
                  onUpdated: () => setState(_reload),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _AdminUserCard extends StatefulWidget {
  const _AdminUserCard({required this.user, required this.onUpdated});
  final JsonMap user;
  final VoidCallback onUpdated;

  @override
  State<_AdminUserCard> createState() => _AdminUserCardState();
}

class _AdminUserCardState extends State<_AdminUserCard> {
  bool _busy = false;
  String? _error;

  String get _id => textOf(widget.user['id'] ?? widget.user['_id']);
  UserRole get _role => roleFrom(widget.user['role']);
  bool get _active =>
      widget.user['isActive'] != false &&
      textOf(widget.user['status']).toLowerCase() != 'inactive';

  Future<void> _update(JsonMap changes) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await apiOf(context).updateUser(_id, changes);
      widget.onUpdated();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            textOf(widget.user['name'] ?? widget.user['fullName'], 'User'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(textOf(widget.user['email'])),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<UserRole>(
                  key: ValueKey('$_id-${_role.name}'),
                  initialValue: _role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: UserRole.values
                      .map(
                        (role) => DropdownMenuItem(
                          value: role,
                          child: Text(role.label),
                        ),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (role) {
                          if (role != null) {
                            _update({'role': role.name});
                          }
                        },
                ),
              ),
              const SizedBox(width: 16),
              Column(
                children: [
                  const Text('Active'),
                  Switch(
                    value: _active,
                    onChanged: _busy
                        ? null
                        : (value) => _update({'isActive': value}),
                  ),
                ],
              ),
            ],
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
  );
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<dynamic>> _notifications;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() => _notifications = apiOf(context).notifications();

  Future<void> _markRead(JsonMap notification) async {
    final id = textOf(notification['id'] ?? notification['_id']);
    if (id.isNotEmpty) {
      try {
        await apiOf(context).markNotificationRead(id);
        if (mounted) setState(_reload);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.toString())));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        PageTitle(
          'Notifications',
          subtitle: 'Updates about your document activity',
          actions: [
            IconButton(
              onPressed: () => setState(_reload),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        Expanded(
          child: AsyncPanel<List<dynamic>>(
            future: _notifications,
            onRetry: () => setState(_reload),
            builder: (context, raw) {
              if (raw.isEmpty) {
                return const EmptyState(
                  'You are all caught up.',
                  icon: Icons.notifications_none,
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: raw.length,
                itemBuilder: (context, index) {
                  final notification = asJson(raw[index]);
                  final read =
                      notification['isRead'] == true ||
                      notification['read'] == true ||
                      notification['readAt'] != null;
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        read
                            ? Icons.notifications_none
                            : Icons.notifications_active_outlined,
                        color: read
                            ? Colors.blueGrey
                            : Theme.of(context).colorScheme.primary,
                      ),
                      title: Text(
                        textOf(
                          notification['title'] ?? notification['subject'],
                          'Document update',
                        ),
                      ),
                      subtitle: Text(
                        textOf(notification['message'] ?? notification['body']),
                      ),
                      trailing: read
                          ? null
                          : IconButton(
                              tooltip: 'Mark as read',
                              onPressed: () => _markRead(notification),
                              icon: const Icon(Icons.done),
                            ),
                      onTap: read ? null : () => _markRead(notification),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({required this.user, super.key});
  final AppUser user;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _baseUrl;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _baseUrl = TextEditingController(
      text: context.read<AppState>().api.baseUrl,
    );
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    super.dispose();
  }

  Future<void> _saveUrl() async {
    setState(() => _saving = true);
    try {
      await apiOf(context).setBaseUrl(_baseUrl.text);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('API base URL saved.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _logout() async {
    try {
      await context.read<AppState>().logout();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 10),
        CircleAvatar(
          radius: 34,
          child: Text(
            widget.user.name.isEmpty ? '?' : widget.user.name[0].toUpperCase(),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          widget.user.name,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(widget.user.email, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Center(child: StatusChip(status: widget.user.role.label)),
        if (widget.user.department.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(widget.user.department, textAlign: TextAlign.center),
          ),
        const SizedBox(height: 28),
        Text('Connection', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextFormField(
          controller: _baseUrl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'API base URL',
            helperText: 'Example: http://10.0.2.2:3000/api',
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _saving ? null : _saveUrl,
          child: _saving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save connection settings'),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: _logout,
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    ),
  );
}
