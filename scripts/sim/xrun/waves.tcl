# xmsim script for WAVES=1: record every signal of the design into waves.shm, then run.
# Open the database with `simvision waves.shm`.
database -open waves -shm -default
probe -create -all -depth all -shm
run
exit
