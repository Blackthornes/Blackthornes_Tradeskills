"""Post a new version's friendly news to the Discord #general channel.

Run by .github/workflows/release.yml after the upload, next to
announce_discord.py (which posts the full changelog in #announcements):

    python tools/post_general.py v0.2.0

The text is the version's section of NEWS.md: one short post in plain words
for players, written with the CHANGELOG section in each release PR. A version
with no NEWS.md section posts nothing.

It posts through a channel webhook kept in the DISCORD_GENERAL_WEBHOOK_URL
repository secret, which the owner makes in Discord (#general > Edit Channel >
Integrations > Webhooks) and pastes into GitHub himself. Without the secret it
does nothing. NEWS.md does not ship in the package, so before posting the
text gets the same clear-to-post scan the package gets (check_package.py's
PRIVATE list), and anything it finds stops the post. Mentions are switched
off, so nothing in it can ping the server.
"""

import glob
import json
import os
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from announce_discord import TAG, section, toc_field, unwrap  # noqa: E402
from check_package import PRIVATE  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIMIT = 1900  # Discord allows 2000 characters in a message; leave room for the link


def not_clear(text):
    """What the clear-to-post scan finds in the post, as a list of labels."""
    return [label for label, pattern in PRIVATE if pattern.search(text)]


def message(project_id, post):
    """The webhook body: the post as written, then the download link."""
    text = unwrap(post)
    if len(text) > LIMIT:
        cut = text.rfind("\n", 0, LIMIT)
        text = text[:cut if cut > 0 else LIMIT].rstrip() + "\n..."
    if project_id:
        text += "\n\nGet it on CurseForge: https://www.curseforge.com/projects/%s" % project_id
    return {"username": "Blackthornes AddOns", "content": text,
            "allowed_mentions": {"parse": []}}


def main(argv):
    if len(argv) != 2 or not TAG.match(argv[1]):
        print("usage: python tools/post_general.py v0.2.0")
        return 2
    hook = os.environ.get("DISCORD_GENERAL_WEBHOOK_URL", "").strip()
    if not hook:
        print("No DISCORD_GENERAL_WEBHOOK_URL secret; not posting in #general.")
        return 0
    version = TAG.match(argv[1]).group(1)
    path = os.path.join(ROOT, "NEWS.md")
    post = None
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            post = section(f.read(), version)
    if not post:
        print("NEWS.md has no section for %s; nothing to post in #general." % version)
        return 0
    found = not_clear(post)
    if found:
        print("Not posting in #general: the post holds %s." % ", ".join(found))
        return 1
    with open(glob.glob(os.path.join(ROOT, "*.toc"))[0], encoding="utf-8") as f:
        toc = f.read()
    body = json.dumps(message(toc_field(toc, "X-Curse-Project-ID"), post))
    req = urllib.request.Request(hook + ("&" if "?" in hook else "?") + "wait=true",
                                 data=body.encode("utf-8"), method="POST",
                                 headers={"Content-Type": "application/json",
                                          "User-Agent": "Blackthornes release"})
    try:
        with urllib.request.urlopen(req, timeout=30):
            pass
    except urllib.error.HTTPError as err:
        # Never print the webhook address: it is the secret.
        print("Discord refused the #general post (%d): %s"
              % (err.code, err.read().decode("utf-8", "replace")[:300]))
        return 1
    except urllib.error.URLError as err:
        print("Could not reach Discord: %s" % err.reason)
        return 1
    print("Posted %s news in #general." % version)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
