import 'dart:async';
import 'dart:convert';
import 'dart:io';

late Map<String, dynamic> myNode;
Socket? relaySocket;

/// Load nodes from rttable0.json
Future<List<Map<String, dynamic>>> loadNodesFromJson(String path) async {
  try {
    final file = File(path);
    if (!await file.exists()) {
      print("rttable0.json file not found at $path");
      exit(1);
    }

    final content = await file.readAsString();
    final jsonData = jsonDecode(content);

    if (jsonData is List) {
      return jsonData.cast<Map<String, dynamic>>();
    } else {
      throw Exception("Invalid JSON format in rttable0.json.");
    }
  } catch (e) {
    print("Error reading rttable0.json: $e");
    exit(1);
  }
}

/// Compute XOR distance between two hex node IDs
int calculateDistance(String a, String b) {
  BigInt aInt = BigInt.parse(a, radix: 16);
  BigInt bInt = BigInt.parse(b, radix: 16);
  return (aInt ^ bInt).toInt();
}

/// Connect to the closest relay node based on XOR distance
Future<Map<String, dynamic>?> connectToBestRelay(List<Map<String, dynamic>> nodes) async {
  String myID = myNode["nodeID"];
  List<Map<String, dynamic>> sorted = List.from(nodes);
  
  //sorted.removeWhere((node) => node["nodeID"] == myID); // Remove self
  sorted.sort((a, b) => calculateDistance(myID, a["nodeID"])
      .compareTo(calculateDistance(myID, b["nodeID"])));

  for (var node in sorted) {
    String ip = node["publicipv4"] ?? "";
    int port = int.tryParse(node["publicipv4port"].toString()) ?? 8888;

    if (ip.isEmpty) continue;

    print("Trying to connect to relay ${node["nodeID"]} at $ip:$port");
    try {
      relaySocket = await Socket.connect(ip, port, timeout: Duration(seconds: 5));
      print("Connected to relay at $ip:$port");

      final registration = {
        "command": "REGISTER",
        "node": myNode,
      };

      relaySocket!.write(jsonEncode(registration));
      print("Sent registration");

      // Incoming messages listener
      relaySocket!.listen(
        (data) {
          final msg = utf8.decode(data);
          print("\n📥 Incoming message: $msg\n");
          stdout.write("Enter message: ");
        },
        onDone: () => print("Disconnected from relay."),
        onError: (e) => print("Error on relay socket: $e"),
      );

      return node;
    } catch (e) {
      print("Failed to connect to $ip:$port - $e");
    }
  }

  print("All relay connection attempts failed.");
  return null;
}

/// Send a message to another node
Future<void> sendMessage(Map<String, dynamic> destination, String message) async {
  if (relaySocket == null) {
    print("Relay socket not connected.");
    return;
  }

  final msg = {
    "destinationNodeHash": destination["nodeID"],
    "sourceNode": myNode,
    "destinationNode": destination,
    "sourceModule": "CM",
    "destinationModule": "CM",
    "query": message,
    "layerID": 0,
    "response": ""
  };

  relaySocket!.write(jsonEncode(msg));
  print("Sent message");
}

Future<void> main() async {
  print("Reading node info...");
  List<Map<String, dynamic>> nodes = await loadNodesFromJson("rttable0.json");

  myNode = nodes.firstWhere(
    (node) => node["isLocal"] == true,
    orElse: () => nodes.first,
  );

  print("Node ID: ${myNode["nodeID"]}");

  Map<String, dynamic>? relayNode = await connectToBestRelay(nodes);
  if (relayNode == null) return;

  // Destination: first node not equal to self
  Map<String, dynamic> destinationNode = nodes.firstWhere(
    (n) => n["nodeID"] != myNode["nodeID"],
    orElse: () => {},
  );

  if (destinationNode.isEmpty) {
    print("No valid destination node found.");
    return;
  }

  // Terminal input loop
  while (true) {
    stdout.write("Enter message: ");
    String input = stdin.readLineSync() ?? "";
    if (input.toLowerCase() == "exit") break;

    await sendMessage(destinationNode, input);
  }

  relaySocket?.destroy();
}
