enum MultiWindowTag {
  history,
  devices;

  static MultiWindowTag getValue(String name) =>
      MultiWindowTag.values.firstWhere(
        (e) => e.name == name,
        orElse: () {
          throw Exception("Unknown Tag $name");
        },
      );
}
