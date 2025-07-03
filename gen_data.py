#!/usr/bin/env python

import sys

def main() -> int:
    end: int = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    dmax: int = int(sys.argv[2]) if len(sys.argv) > 2 else 5

    half: int = end // 2 + (1 if end % 2 == 1 else 0)
    for i in range(1, end):
        count = max(int((1 - abs(half - i) / half) * dmax), 1)
        print(f"{i}\n" * count, end="")


if __name__ == "__main__":
    main()
