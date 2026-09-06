#!/usr/bin/env python3
"""Build a daily TikTok account and comment monitoring report."""

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ACCOUNTS_PATH = ROOT / "monitoring" / "tiktok_accounts.json"
TOKEN_URL = "https://open.tiktokapis.com/v2/oauth/token/"
PROFILE_URL = "https://open.tiktokapis.com/v2/user/info/"
PROFILE_FIELDS = "open_id,display_name,follower_count,following_count,likes_count,video_count"
POSITIVE_WORDS = {"good", "great", "excellent", "love", "helpful", "thanks", "thank", "best", "profit", "win"}
NEGATIVE_WORDS = {"bad", "scam", "fake", "loss", "lost", "refund", "problem", "hate", "worst", "fraud"}


def request_json(url, *, method="GET", data=None, access_token=None):
    headers = {"Accept": "application/json"}
    if access_token:
        headers["Authorization"] = f"Bearer {access_token}"
    if data is not None:
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        data = urllib.parse.urlencode(data).encode("utf-8")
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def refresh_access_token(account):
    try:
        response = request_json(
            TOKEN_URL,
            method="POST",
            data={
                "client_key": os.environ["TIKTOK_CLIENT_KEY"],
                "client_secret": os.environ["TIKTOK_CLIENT_SECRET"],
                "grant_type": "refresh_token",
                "refresh_token": account["refresh_token"],
            },
        )
        if "access_token" not in response:
            raise RuntimeError(response.get("message", "TikTok did not return an access token"))
        return response["access_token"], None
    except (KeyError, urllib.error.URLError, urllib.error.HTTPError, RuntimeError, json.JSONDecodeError) as error:
        return None, str(error)


def profile_for(access_token):
    url = f"{PROFILE_URL}?{urllib.parse.urlencode({'fields': PROFILE_FIELDS})}"
    response = request_json(url, access_token=access_token)
    if response.get("error", {}).get("code", "ok") != "ok":
        raise RuntimeError(response["error"].get("message", "TikTok profile request failed"))
    return response["data"]["user"]


def comments_for(access_token, open_id):
    template = os.environ.get("TIKTOK_COMMENTS_URL_TEMPLATE", "").strip()
    if not template:
        return [], "Comments endpoint is not configured."
    try:
        response = request_json(template.format(open_id=urllib.parse.quote(open_id, safe="")), access_token=access_token)
        data = response.get("data", response)
        comments = data.get("comments", data.get("items", []))
        if not isinstance(comments, list):
            raise RuntimeError("The comments response did not contain a comments list.")
        return comments, None
    except (urllib.error.URLError, urllib.error.HTTPError, RuntimeError, json.JSONDecodeError) as error:
        return [], str(error)


def comment_text(comment):
    return str(comment.get("text", comment.get("comment_text", ""))).strip()


def sentiment(comments):
    counts = Counter()
    keywords = Counter()
    for comment in comments:
        words = {word.strip(".,!?;:()[]{}\"'").lower() for word in comment_text(comment).split()}
        positive = words & POSITIVE_WORDS
        negative = words & NEGATIVE_WORDS
        if positive and not negative:
            counts["positive"] += 1
            keywords.update(positive)
        elif negative and not positive:
            counts["negative"] += 1
            keywords.update(negative)
        else:
            counts["neutral"] += 1
    return counts, keywords


def main():
    try:
        secret_accounts = json.loads(os.environ["TIKTOK_MONITOR_ACCOUNTS"])
        configured_accounts = json.loads(ACCOUNTS_PATH.read_text(encoding="utf-8"))
    except (KeyError, json.JSONDecodeError, OSError) as error:
        print(f"Configuration error: {error}", file=sys.stderr)
        return 1

    credentials = {entry.get("handle", "").lower(): entry for entry in secret_accounts}
    lines = [
        "# TikTok monitoring report",
        "",
        f"Generated: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')}",
        "",
        "| Account | Followers | Following | Likes | Videos | Comment summary |",
        "|---|---:|---:|---:|---:|---|",
    ]
    warnings = []
    findings = []

    for configured in configured_accounts:
        handle = configured["handle"]
        account = credentials.get(handle.lower())
        if not account or "refresh_token" not in account:
            warnings.append(f"{handle}: no refresh token was supplied in `TIKTOK_MONITOR_ACCOUNTS`.")
            continue
        access_token, token_error = refresh_access_token(account)
        if token_error:
            warnings.append(f"{handle}: token refresh failed — {token_error}")
            continue
        try:
            profile = profile_for(access_token)
        except (urllib.error.URLError, urllib.error.HTTPError, RuntimeError, KeyError, json.JSONDecodeError) as error:
            warnings.append(f"{handle}: profile request failed — {error}")
            continue

        comments, comment_error = comments_for(access_token, profile["open_id"])
        counts, keywords = sentiment(comments)
        if comment_error:
            summary=comment_error
        else:
            summary=f"{len(comments)} reviewed; {counts['positive']} positive, {counts['negative']} negative"
            if counts["negative"]:
                findings.append(f"{handle}: negative-comment keywords — {', '.join(word for word, _ in keywords.most_common(5)) or 'none'}")
        lines.append(
            f"| {handle} | {profile.get('follower_count', 'N/A')} | {profile.get('following_count', 'N/A')} | "
            f"{profile.get('likes_count', 'N/A')} | {profile.get('video_count', 'N/A')} | {summary} |"
        )

    if findings:
        lines.extend(["", "## Attention needed", *[f"- {finding}" for finding in findings]])
    if warnings:
        lines.extend(["", "## Collection warnings", *[f"- {warning}" for warning in warnings]])
    lines.extend(["", "## Notes", "- Reports use only data returned by TikTok for accounts that authorized the app and scopes."])
    Path(os.environ.get("REPORT_PATH", "tiktok-report.md")).write_text("\n".join(lines) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
