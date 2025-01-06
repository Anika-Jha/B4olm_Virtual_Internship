/*
NAT Detection with Dart
This project uses Dart to detect the network setup of a device by listing all connected network interfaces, identifying their IP addresses (both IPv4 and IPv6), and determining if the device is behind a NAT. 
It also retrieves the public IP address using the Google STUN server.

Features
Fetch All Network Interfaces: Lists all connected network interfaces and their IP addresses, including IPv4 and IPv6.
Private vs Public IP Detection: Identifies whether an IP address is private (indicating NAT) or public.
Public IP & Port Retrieval
NAT Status Check: Determines whether the device is behind a NAT.
Determines the type of NAT the device is behind.

This code is a Dart program that analyzes the network environment of the local device, determines its local and public IP addresses, and identifies the type of NAT (Network Address Translation) the device is behind.
*/

import 'dart:io';
import 'dart:typed_data';

class NetworkManager {
  // Retrieve and print all interfaces and their IP addresses
  Future<void> printNetworkInterfaces() async {
    try {
      var interfaces = await NetworkInterface.list(includeLinkLocal: true);
      print('Available Network Interfaces:');
      bool ipv4Found = false;

      for (var interface in interfaces) {
        print('== Interface: ${interface.name} ==');
        for (var addr in interface.addresses) {
          String type = addr.type == InternetAddressType.IPv4 ? 'IPv4' : 'IPv6';
          bool isPrivate = isPrivateIP(addr.address);
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
  //it iterates over network interfaces
  //Filters out IPv4 and IPv6 addresses and stores them in a map.
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
  //Checks if the IP is private or public 
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

  // Use Google STUN server to get the public IP and port
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
      final transactionId = List<int>.generate(12, (i) => i);
      final stunMessage = Uint8List.fromList([
        0x00, 0x01, 0x00, 0x00,
        0x21, 0x12, 0xA4, 0x42,
        ...transactionId,
      ]);

      socket.send(stunMessage, stunServerAddress.first, stunPort);

      //can be null also 
      String? publicIP; //textual in nature
      int? publicPort; //port nos. are integers

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

  // Define the type of NAT based on STUN server responses
  //Makes two connections to the same STUN server and port and records the public IP and port for each connection.
  Future<String> defineNATType(String stunServer, int stunPort) async {
  try {
    var connection1 = await getPublicIPAndPort(stunServer, stunPort);
    if (connection1 == null) {
      return "NAT Type: Unknown (Failed to retrieve public IP and port)";
    }

    var connection2 = await getPublicIPAndPort(stunServer, stunPort);
    if (connection2 == null) {
      return "NAT Type: Unknown (Failed to retrieve public IP and port)";
    }

    // Symmetric NAT: Public IP or port changes with each request
    if (connection1['ip'] != connection2['ip'] && connection1['port'] != connection2['port']) {
      return "NAT Type: Symmetric NAT";
    }

    // Port-Restricted NAT: Public IP is the same, but port changes for different destinations
    if (connection1['ip'] == connection2['ip'] || connection1['port'] != connection2['port']) {
      return "NAT Type: Port-Restricted NAT";
    }

    // Address-Restricted NAT: Public IP remains the same, but only specific destination ports can be used
    if (connection1['ip'] == connection2['ip'] && connection1['port'] == connection2['port']) {
      return "NAT Type: Address-Restricted NAT";
    }

    // Full Cone NAT: Public IP and port remain consistent
    return "NAT Type: Full Cone NAT";
  } catch (e) {
    return "Error defining NAT type: $e";
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

    var natType = await defineNATType('stun.l.google.com', 19302);
    print('\n$natType');
  }
}

void main() async {
  var networkManager = NetworkManager();
  await networkManager.checkNATStatus();
}
