// class CallLogModel {
//   final String name;
//   final String phoneNumber;
//   final String time;
//   final String callType;

//   CallLogModel({
//     required this.name,
//     required this.phoneNumber,
//     required this.time,
//     required this.callType,
//   });
// }

// class ContactQueueItem {
//   final int id;
//   final String name;
//   final String phoneNumber;
//   final String details;
//   final String status;
//   final String? topQuestion;

//   ContactQueueItem({
//     required this.id,
//     required this.name,
//     required this.phoneNumber,
//     required this.details,
//     required this.status,
//     this.topQuestion,
//   });

//   factory ContactQueueItem.fromJson(Map<String, dynamic> json) {
//     return ContactQueueItem(
//       id: json['id'],
//       name: json['name'],
//       phoneNumber: json['phone_number'],
//       details: json['details'] ?? 'No details provided',
//       status: json['status'] ?? 'PENDING',
//       topQuestion: json['top_question'],
//     );
//   }
// }

class CallLogModel {
  final String name;
  final String phoneNumber;
  final String time;
  final String callType;

  CallLogModel({
    required this.name,
    required this.phoneNumber,
    required this.time,
    required this.callType,
  });
}

class ContactQueueItem {
  final int id;
  final String name;
  final String phoneNumber;
  final String details;
  final String status;
  final String? topQuestion;

  ContactQueueItem({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.details,
    required this.status,
    this.topQuestion,
  });

  factory ContactQueueItem.fromJson(Map<String, dynamic> json) {
    return ContactQueueItem(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      phoneNumber: json['phone_number'] ?? '',
      details: json['details'] ?? 'No details provided',
      status: json['status'] ?? 'PENDING',
      topQuestion: json['top_question'],
    );
  }
}
