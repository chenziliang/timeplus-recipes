# Examine the timesplud logs

# Network errors
k@t+ 20250119-logs % rg "<Error> client"  node*.errs | rg "error=(\w+)" -or '$1' | sort | uniq -c | sort -bgr
3241119 ECANCELED
4932 EBADF
3503 EPIPE
1332 ECONNREFUSED
 886 EHOSTUNREACH
  16 ETIMEDOUT
  16 EAI_NONAME
   8 ECONNRESET