# Big block

A block with more than 100 lines, to exercise the 3-digit gutter width
(`--ln-digits` bumps from 2 to 3 at 100 lines).

```julia
function build_lookup_table()
    table = Dict{Int,Int}()
    table[1] = 1   # square of 1
    table[2] = 4   # square of 2
    table[3] = 9   # square of 3
    table[4] = 16   # square of 4
    table[5] = 25   # square of 5
    table[6] = 36   # square of 6
    table[7] = 49   # square of 7
    table[8] = 64   # square of 8
    table[9] = 81   # square of 9
    table[10] = 100   # square of 10
    table[11] = 121   # square of 11
    table[12] = 144   # square of 12
    table[13] = 169   # square of 13
    table[14] = 196   # square of 14
    table[15] = 225   # square of 15
    table[16] = 256   # square of 16
    table[17] = 289   # square of 17
    table[18] = 324   # square of 18
    table[19] = 361   # square of 19
    table[20] = 400   # square of 20
    table[21] = 441   # square of 21
    table[22] = 484   # square of 22
    table[23] = 529   # square of 23
    table[24] = 576   # square of 24
    table[25] = 625   # square of 25
    table[26] = 676   # square of 26
    table[27] = 729   # square of 27
    table[28] = 784   # square of 28
    table[29] = 841   # square of 29
    table[30] = 900   # square of 30
    table[31] = 961   # square of 31
    table[32] = 1024   # square of 32
    table[33] = 1089   # square of 33
    table[34] = 1156   # square of 34
    table[35] = 1225   # square of 35
    table[36] = 1296   # square of 36
    table[37] = 1369   # square of 37
    table[38] = 1444   # square of 38
    table[39] = 1521   # square of 39
    table[40] = 1600   # square of 40
    table[41] = 1681   # square of 41
    table[42] = 1764   # square of 42
    table[43] = 1849   # square of 43
    table[44] = 1936   # square of 44
    table[45] = 2025   # square of 45
    table[46] = 2116   # square of 46
    table[47] = 2209   # square of 47
    table[48] = 2304   # square of 48
    table[49] = 2401   # square of 49
    table[50] = 2500   # square of 50
    table[51] = 2601   # square of 51
    table[52] = 2704   # square of 52
    table[53] = 2809   # square of 53
    table[54] = 2916   # square of 54
    table[55] = 3025   # square of 55
    table[56] = 3136   # square of 56
    table[57] = 3249   # square of 57
    table[58] = 3364   # square of 58
    table[59] = 3481   # square of 59
    table[60] = 3600   # square of 60
    table[61] = 3721   # square of 61
    table[62] = 3844   # square of 62
    table[63] = 3969   # square of 63
    table[64] = 4096   # square of 64
    table[65] = 4225   # square of 65
    table[66] = 4356   # square of 66
    table[67] = 4489   # square of 67
    table[68] = 4624   # square of 68
    table[69] = 4761   # square of 69
    table[70] = 4900   # square of 70
    table[71] = 5041   # square of 71
    table[72] = 5184   # square of 72
    table[73] = 5329   # square of 73
    table[74] = 5476   # square of 74
    table[75] = 5625   # square of 75
    table[76] = 5776   # square of 76
    table[77] = 5929   # square of 77
    table[78] = 6084   # square of 78
    table[79] = 6241   # square of 79
    table[80] = 6400   # square of 80
    table[81] = 6561   # square of 81
    table[82] = 6724   # square of 82
    table[83] = 6889   # square of 83
    table[84] = 7056   # square of 84
    table[85] = 7225   # square of 85
    table[86] = 7396   # square of 86
    table[87] = 7569   # square of 87
    table[88] = 7744   # square of 88
    table[89] = 7921   # square of 89
    table[90] = 8100   # square of 90
    table[91] = 8281   # square of 91
    table[92] = 8464   # square of 92
    table[93] = 8649   # square of 93
    table[94] = 8836   # square of 94
    table[95] = 9025   # square of 95
    table[96] = 9216   # square of 96
    table[97] = 9409   # square of 97
    table[98] = 9604   # square of 98
    table[99] = 9801   # square of 99
    table[100] = 10000   # square of 100
    table[101] = 10201   # square of 101
    table[102] = 10404   # square of 102
    table[103] = 10609   # square of 103
    table[104] = 10816   # square of 104
    table[105] = 11025   # square of 105
    return table
end
```

