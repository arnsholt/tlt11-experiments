BEGIN { OFS = "\t"; }

NF > 0 {
    $2 = "_";
    $3 = "_";
}

{ print }
