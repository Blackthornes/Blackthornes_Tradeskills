"""Tests for tools/post_general.py. Run: python tools/test_post_general.py"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from announce_discord import section  # noqa: E402
from post_general import main, message, not_clear  # noqa: E402

NEWS = ("# News\n\n## 0.2.0\n\nHey everyone! A new update is out.\nIt fixes\n"
        "the map. Thanks @everyone for the reports!\n\n## 0.1.0\n\nFirst.\n")

checks = 0
failures = 0


def expect(label, ok):
    global checks, failures
    checks += 1
    if not ok:
        failures += 1
        print("FAIL: " + label)


post = section(NEWS, "0.2.0")
body = message("123", post)
expect("the post is the version's section, lines joined",
       body["content"].startswith("Hey everyone! A new update is out. It fixes the map."))
expect("ends with the CurseForge link",
       body["content"].endswith("https://www.curseforge.com/projects/123"))
expect("nothing in it can ping", body["allowed_mentions"] == {"parse": []})
expect("posted as the house name", body["username"] == "Blackthornes AddOns")
expect("no project ID, no link", "curseforge" not in message(None, "Hi.")["content"])
long_post = "\n\n".join("Paragraph %d of a very long post about the update." % i for i in range(200))
expect("a long post fits in one message", len(message("1", long_post)["content"]) <= 2000)

expect("a plain post is clear to post", not_clear(post) == [])
expect("a Windows path is caught", "a Windows path" in not_clear("See D:\\Games\\WoW for it."))
expect("an email address is caught", "an email address" in not_clear("Mail me at someone@example.com"))
expect("the owner's name is caught", "the owner's name" in not_clear("Thanks, " + "Tr" + "ent"))

os.environ.pop("DISCORD_GENERAL_WEBHOOK_URL", None)
expect("without the secret it does nothing and succeeds", main(["x", "v0.2.0"]) == 0)
expect("a bad tag is refused", main(["x", "next"]) == 2)

print("  post_general: %d checks, %d failure(s)" % (checks, failures))
sys.exit(1 if failures else 0)
