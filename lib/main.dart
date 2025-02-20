import 'dart:async';

import 'package:amplify_api/amplify_api.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_authenticator/amplify_authenticator.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/material.dart';

import 'amplify_outputs.dart';
import 'models/ModelProvider.dart';

Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await _configureAmplify();
    runApp(const MyApp());
  } on AmplifyException catch (e) {
    runApp(Text("Error configuring Amplify: ${e.message}"));
  }
}

Future<void> _configureAmplify() async {
  try {
    await Amplify.addPlugins(
      [
        AmplifyAuthCognito(),
        AmplifyAPI(
          options: APIPluginOptions(
            modelProvider: ModelProvider.instance,
            baseHttpClient: MyHttpRequestInterceptor(),
          ),
        ),
      ],
    );
    await Amplify.configure(amplifyConfig);
    safePrint('Successfully configured');
  } on Exception catch (e) {
    safePrint('Error configuring Amplify: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return Authenticator(
      child: MaterialApp(
        builder: Authenticator.builder(),
        home: const SafeArea(
          child: Scaffold(
            body: Column(
              children: [
                SignOutButton(),
                Expanded(child: TodoScreen()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TodoScreen extends StatefulWidget {
  const TodoScreen({super.key});

  @override
  State<TodoScreen> createState() => _TodoScreenState();
}

class _TodoScreenState extends State<TodoScreen> {
  List<Todo> _todos = [];

  StreamSubscription<GraphQLResponse<Todo>>? subscription;

  @override
  void initState() {
    super.initState();
    _refreshTodos();
    _subscribe();
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  void _subscribe() {
    final subscriptionRequest = ModelSubscriptions.onCreate(Todo.classType);
    final Stream<GraphQLResponse<Todo>> operation = Amplify.API.subscribe(
      subscriptionRequest,
      onEstablished: () => safePrint('Subscription established'),
    );
    subscription = operation.listen(
      (event) {
        safePrint('Subscription event data received: ${event.data}');
        setState(() {
          _todos.add(event.data!);
        });
      },
      onError: (Object e) => safePrint('Error in subscription stream: $e'),
    );
  }

  void _unsubscribe() {
    subscription?.cancel();
    subscription = null;
  }

  Future<void> _refreshTodos() async {
    try {
      final userPoolRequest = ModelQueries.list(Todo.classType,
          authorizationMode: APIAuthorizationType.userPools);
      final userPoolResponse =
          await Amplify.API.query(request: userPoolRequest).response;

      final todos = userPoolResponse.data?.items;
      if (userPoolResponse.hasErrors) {
        safePrint('errors: ${userPoolResponse.errors}');
        return;
      }
      setState(() {
        _todos = todos!.whereType<Todo>().toList();
      });
    } on ApiException catch (e) {
      safePrint('Query failed: $e');
    }
  }

  Future<void> queryWithCustomHeaders() async {
    final operation = Amplify.API.query<String>(
      request: GraphQLRequest(
        document: 'graphQLDocumentString',
        headers: {'customHeader': 'someValue'},
      ),
    );
    final response = await operation.response;
    final data = response.data;
    safePrint('data: $data');
  }

  Future<Todo?> queryItem(Todo queriedTodo) async {
    try {
      final request = ModelQueries.get(
        Todo.classType,
        queriedTodo.modelIdentifier,
      );
      final response = await Amplify.API.query(request: request).response;
      final todo = response.data;
      if (todo == null) {
        safePrint('errors: ${response.errors}');
      }
      return todo;
    } on ApiException catch (e) {
      safePrint('Query failed: $e');
      return null;
    }
  }

  Future<List<Todo?>> queryListItems() async {
    try {
      final request = ModelQueries.list(Todo.classType);
      final response = await Amplify.API.query(request: request).response;

      final todos = response.data?.items;
      if (todos == null) {
        safePrint('errors: ${response.errors}');
        return const [];
      }
      return todos;
    } on ApiException catch (e) {
      safePrint('Query failed: $e');
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        label: const Text('Add Random Todo'),
        onPressed: () async {
          await addItem();

          safePrint(queryListItems());
        },
      ),
      body: _todos.isEmpty == true
          ? const Center(
              child: Text(
                "The list is empty.\nAdd some items by clicking the floating action button.",
                textAlign: TextAlign.center,
              ),
            )
          : ListView.builder(
              itemCount: _todos.length,
              itemBuilder: (context, index) {
                final todo = _todos[index];
                return Dismissible(
                  key: UniqueKey(),
                  confirmDismiss: (direction) async {
                    return await deleteItem(direction, todo);
                  },
                  child: CheckboxListTile.adaptive(
                    value: todo.isDone,
                    title: Text(todo.content!),
                    onChanged: (isChecked) async {
                      await loadItems(todo, isChecked);
                    },
                  ),
                );
              },
            ),
    );
  }

  Future<void> loadItems(Todo todo, bool? isChecked) async {
    final request = ModelMutations.update(
      todo.copyWith(isDone: isChecked!),
    );
    final response = await Amplify.API.mutate(request: request).response;
    if (response.hasErrors) {
      safePrint('Updating Todo failed. ${response.errors}');
    } else {
      safePrint('Updating Todo successful.');
      await _refreshTodos();
    }
  }

  Future<bool> deleteItem(DismissDirection direction, Todo todo) async {
    if (direction == DismissDirection.endToStart) {
      final request = ModelMutations.delete(todo);
      final response = await Amplify.API.mutate(request: request).response;
      if (response.hasErrors) {
        safePrint('Updating Todo failed. ${response.errors}');
      } else {
        safePrint('Updating Todo successful.');
        await _refreshTodos();
        return true;
      }
    }
    return false;
  }

  Future<void> addItem() async {
    final newTodo = Todo(
      id: uuid(),
      content: "Random Todo ${DateTime.now().toIso8601String()}",
      isDone: false,
    );
    final request = ModelMutations.create(newTodo);
    final response = await Amplify.API.mutate(request: request).response;
    if (response.hasErrors) {
      safePrint('Creating Todo failed.');
    } else {
      safePrint('Creating Todo successful.');
    }
    _refreshTodos();
  }
}

// First create a custom HTTP client implementation to extend HTTP functionality.
class MyHttpRequestInterceptor extends AWSBaseHttpClient {
  @override
  Future<AWSBaseHttpRequest> transformRequest(
    AWSBaseHttpRequest request,
  ) async {
    request.headers.putIfAbsent('customHeader', () => 'someValue');
    return request;
  }
}
