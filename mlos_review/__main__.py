"""`python3 -m mlos_review [results.json]` -- display-name coverage report.

Lists every machine name in a bundle that the vocabulary had to render with
the fallback tokenizer, which is the standing to-do list for curating wording.
"""

import sys

from mlos_review.names import main

if __name__ == "__main__":
    raise SystemExit(main(["mlos_review"] + sys.argv[1:]))
