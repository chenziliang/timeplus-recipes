#!/bin/bash

timeplusd client --query "EXPLAIN pipeline graph=1, compact=0 ...query..." | dot  -Tpdf > pipeline.pdf 