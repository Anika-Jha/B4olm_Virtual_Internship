/*
NAT Detection with Dart
This project uses Dart to detect the network setup of a device by listing all connected network interfaces, identifying their IP addresses (both IPv4 and IPv6), and determining if the device is behind a NAT. 
It also retrieves the public IP address using the Google STUN server.

Features
Fetch All Network Interfaces: Lists all connected network interfaces and their IP addresses, including IPv4 and IPv6.
Private vs Public IP Detection: Identifies whether an IP address is private (indicating NAT) or public.
Public IP & Port Retrieval
NAT Status Check: Determines whether the device is behind a NAT.
*/

import 'dart:io';
import 'dart:typed_data';

class NetworkManager {
  // Retrieve and print all interfaces and their IP addresses
  Future<void> printNetworkInterfaces() async {
    try {
      var interfaces = await NetworkInterface.list(includeLinkLocal: true);
      print('Available Network Interfaces:');
      bool ipv4Found = false; // Flag to track IPv4 addresses

      for (var interface in interfaces) {
        print('== Interface: ${interface.name} ==');
        for (var addr in interface.addresses) {
          String type = addr.type == InternetAddressType.IPv4 ? 'IPv4' : 'IPv6';
          bool isPrivate = isPrivateIP(addr.address);

          // Print each address and mark whether it's public or private
          print('$type Address: ${addr.address} (${isPrivate ? "Private" : "Public"})');

          if (addr.type == InternetAddressType.IPv4) {
            ipv4Found = true;
          }
        }
      }

      if (!ipv4Found) {
        print('No IPv4 address found on the local device.');
      }
    } catch (e) {
      print('Error retrieving network interfaces: $e');
    }
  }

  // Retrieve local IPv4 and IPv6 addresses
  Future<Map<String, String>> getLocalIPs() async {
    Map<String, String> localIPs = {};

    try {
      var interfaces = await NetworkInterface.list(includeLinkLocal: true);
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            localIPs['IPv4'] = addr.address;
          } else if (addr.type == InternetAddressType.IPv6) {
            localIPs['IPv6'] = addr.address;
          }
        }
      }
    } catch (e) {
      print('Error retrieving local IPs: $e');
    }

    return localIPs;
  }

  // Check if the given IP address is private (indicating NAT)
  bool isPrivateIP(String ip) {
    final privateRanges = [
      '10.', '172.', '192.168.', // Private IPv4 ranges
      'fc00::', 'fd00::' // Private IPv6 ranges
    ];

    for (var range in privateRanges) {
      if (ip.startsWith(range)) {
        return true; // NAT detected (private IP)
      }
    }
    return false; // Public IP
  }

  // Use Google STUN server to get the public IP address and port
  Future<Map<String, dynamic>?> getPublicIPAndPort(String stunServer, int stunPort) async {
    try {
      var stunServerAddress = (await InternetAddress.lookup(stunServer))
          .where((addr) => addr.type == InternetAddressType.IPv4)
          .toList();

      if (stunServerAddress.isEmpty) {
        print('Failed to resolve STUN server address.');
        return null;
      }

      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      print('Using local port: ${socket.port} to communicate with $stunServer:$stunPort');

      // STUN binding request
      final transactionId = List<int>.generate(12, (i) => i);
      final stunMessage = Uint8List.fromList([
        0x00, 0x01, 0x00, 0x00,
        0x21, 0x12, 0xA4, 0x42,
        ...transactionId,
      ]);

      socket.send(stunMessage, stunServerAddress.first, stunPort);
      print('STUN request sent to ${stunServerAddress.first}:$stunPort.');

      String? publicIP;
      int? publicPort;

      await for (var event in socket) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram != null) {
            final response = datagram.data;
            if (response.length >= 28) {
              final addressFamily = response[25];
              if (addressFamily == 0x01) {
                publicIP = [
                  response[28] ^ 0x21,
                  response[29] ^ 0x12,
                  response[30] ^ 0xA4,
                  response[31] ^ 0x42
                ].join('.');
                publicPort = ((response[26] & 0xFF) << 8) | (response[27] & 0xFF);
                print('Public IP retrieved: $publicIP');
                print('Public Port retrieved: $publicPort');
                break;
              }
            }
          }
        }
      }

      socket.close();
      return {'ip': publicIP, 'port': publicPort};
    } catch (e) {
      print('Error retrieving public IP via STUN: $e');
      return null;
    }
  }

  // Main function to check NAT status
  Future<void> checkNATStatus() async {
    await printNetworkInterfaces();

    var connectionInfo = await getPublicIPAndPort('stun.l.google.com', 19302);
    if (connectionInfo != null) {
      print("Public IP: ${connectionInfo['ip']}");
      print("Public Port: ${connectionInfo['port']}");
    } else {
      print("Failed to determine public IP and port.");
    }

    var localIPs = await getLocalIPs();
    print('\nLocal IPs of the Device:');
    localIPs.forEach((type, ip) {
      print('$type: $ip');
    });
  }
}

void main() async {
  var networkManager = NetworkManager();
  await networkManager.checkNATStatus();
}

