typedef DataHandler<T> = void Function(T data);
typedef DoneHandler = void Function();
typedef VoidCallback<T> = T Function();
typedef ErrorHandler = void Function(Object error, StackTrace stackTrace);

const int tagData = 0;
const int tagError = 1;
const int tagDone = 2;
