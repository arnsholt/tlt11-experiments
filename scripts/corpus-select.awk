BEGIN {
    RS = ""
    FS = "\n"
}

{
    print $0 "\n"
    if(NR >= count)
        exit
}
