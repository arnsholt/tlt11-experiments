BEGIN {
    OFS = "\t"
    while(getline < base) {
        if(NF == 0) continue
        words[$2] = 1
    }
}

NF > 0 {
    if($2 in words) seen[$2]++
}

END {
    for(x in seen) {
        print x, seen[x]
    }
}
