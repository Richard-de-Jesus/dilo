#include<errno.h>

void setErrno(int code) {
  errno = code;
}
