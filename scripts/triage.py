#!/usr/bin/env python3
"""
Issue triage: analyze, classify, and label GitHub issues.
"""

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from typing import Optional

# Label detection patterns
LABEL_PATTERNS = {
    "bug": [
        r"\berror\b", r"\bcrash\b", r"\bdoesn'?t work\b", r"\bbroken\b",
        r"\bfail\b", r"\bexception\b", r"\bbug\b", r"\bissue\b",
        r"\bproblem\b", r"\bincorrect\b", r"\bwrong\b", r"\bnot working\b"
    ],
    "enhancement": [
        r"\bfeature\b", r"\badd\b", r"\bsupport\b", r"\bwould be nice\b",
        r"\bcould\b", r"\bshould\b", r"\bwish\b", r"\bwant\b",
        r"\brequest\b", r"\bimprove\b", r"\benhance\b"
    ],
    "documentation": [
        r"\bdocs?\b", r"\breadme\b", r"\bexample\b", r"\bdocumentation\b",
        r"\bguide\b", r"\btutorial\b", r"\bexplain\b"
    ],
    "question": [
        r"\bhow\b", r"\bwhat\b", r"\bwhy\b", r"\bhelp\b", r"\bquestion\b",
        r"\bconfused\b", r"\bunderstand\b", r"\bwondering\b"
    ],
    "security": [
        r"\bsecurity\b", r"\bvulnerability\b", r"\bcve\b", r"\bexploit\b",
        r"\bxss\b", r"\binjection\b", r"\bauth\b", r"\bcredential\b"
    ],
    "performance": [
        r"\bslow\b", r"\bperformance\b", r"\boptimize\b", r"\bspeed\b",
        r"\bmemory\b", r"\bcpu\b", r"\bbottleneck\b"
    ]
}

# Priority indicators
PRIORITY_INDICATORS = {
    "P0": [  # Critical
        r"\bsecurity\b", r"\bdata loss\b", r"\bproduction\b", r"\boutage\b",
        r"\bcritical\b", r"\burgent\b", r"\bemergency\b"
    ],
    "P1": [  # High
        r"\bregression\b", r"\bbreaking\b", r"\bworkaround\b"
    ],
    "P2": [  # Normal
        # Default for most issues
    ],
    "P3": [  # Low
        r"\bnice to have\b", r"\bsomeday\b", r"\blow priority\b",
        r"\bminor\b", r"\bpolish\b"
    ]
}


@dataclass
class IssueAnalysis:
    number: int
    title: str
    body: str
    author: str
    existing_labels: list[str]
    
    # Computed
    suggested_labels: list[str]
    priority: str
    confidence: float
    needs_clarification: bool
    clarification_questions: list[str]


def detect_labels(text: str) -> tuple[list[str], float]:
    """Detect labels from text, return labels and confidence."""
    text_lower = text.lower()
    detected = {}
    
    for label, patterns in LABEL_PATTERNS.items():
        matches = sum(1 for p in patterns if re.search(p, text_lower))
        if matches > 0:
            detected[label] = matches
    
    if not detected:
        return [], 0.0
    
    # Sort by match count
    sorted_labels = sorted(detected.items(), key=lambda x: -x[1])
    top_labels = [l for l, _ in sorted_labels[:2]]
    
    # Confidence based on match strength
    total_matches = sum(detected.values())
    confidence = min(0.9, 0.5 + (total_matches * 0.1))
    
    return top_labels, confidence


def detect_priority(text: str) -> str:
    """Detect issue priority from text."""
    text_lower = text.lower()
    
    for priority, patterns in PRIORITY_INDICATORS.items():
        if any(re.search(p, text_lower) for p in patterns):
            return priority
    
    return "P2"  # Default


def needs_clarification(title: str, body: str) -> tuple[bool, list[str]]:
    """Check if issue needs clarification, return questions to ask."""
    questions = []
    text = f"{title}\n{body}".lower()
    
    # Check for missing key information
    if len(body) < 50:
        questions.append("Could you provide more details about the issue?")
    
    if "reproduce" not in text and "steps" not in text and "bug" in text:
        questions.append("What are the steps to reproduce this issue?")
    
    if "expected" not in text and "actual" not in text:
        questions.append("What's the expected behavior vs actual behavior?")
    
    if not any(word in text for word in ["version", "environment", "os", "node", "rust"]):
        questions.append("What version/environment are you running?")
    
    return len(questions) > 0, questions


def analyze_issue(repo: str, issue_number: int) -> Optional[IssueAnalysis]:
    """Fetch and analyze an issue."""
    # Get issue data via gh CLI
    result = subprocess.run(
        ["gh", "issue", "view", str(issue_number), "--repo", repo, "--json",
         "number,title,body,author,labels"],
        capture_output=True, text=True
    )
    
    if result.returncode != 0:
        print(f"Error fetching issue: {result.stderr}", file=sys.stderr)
        return None
    
    data = json.loads(result.stdout)
    
    title = data.get("title", "")
    body = data.get("body", "") or ""
    author = data.get("author", {}).get("login", "unknown")
    existing_labels = [l["name"] for l in data.get("labels", [])]
    
    # Analyze
    full_text = f"{title}\n{body}"
    suggested_labels, confidence = detect_labels(full_text)
    priority = detect_priority(full_text)
    needs_clarify, questions = needs_clarification(title, body)
    
    return IssueAnalysis(
        number=issue_number,
        title=title,
        body=body,
        author=author,
        existing_labels=existing_labels,
        suggested_labels=suggested_labels,
        priority=priority,
        confidence=confidence,
        needs_clarification=needs_clarify,
        clarification_questions=questions
    )


def apply_labels(repo: str, issue_number: int, labels: list[str], dry_run: bool = False) -> bool:
    """Apply labels to an issue."""
    if not labels:
        return True
    
    if dry_run:
        print(f"  Would add labels: {', '.join(labels)}")
        return True
    
    result = subprocess.run(
        ["gh", "issue", "edit", str(issue_number), "--repo", repo,
         "--add-label", ",".join(labels)],
        capture_output=True, text=True
    )
    
    return result.returncode == 0


def add_comment(repo: str, issue_number: int, comment: str, dry_run: bool = False) -> bool:
    """Add a comment to an issue."""
    if dry_run:
        print(f"  Would comment: {comment[:100]}...")
        return True
    
    result = subprocess.run(
        ["gh", "issue", "comment", str(issue_number), "--repo", repo,
         "--body", comment],
        capture_output=True, text=True
    )
    
    return result.returncode == 0


def generate_clarification_comment(questions: list[str]) -> str:
    """Generate a friendly clarification comment."""
    if not questions:
        return ""
    
    comment = "Thanks for opening this issue! To help me understand and address it, could you provide:\n\n"
    for q in questions:
        comment += f"- {q}\n"
    comment += "\nOnce I have this information, I'll be able to work on a fix."
    return comment


def main():
    parser = argparse.ArgumentParser(description="Triage GitHub issues")
    parser.add_argument("repo", help="Repository (owner/repo)")
    parser.add_argument("--issue", type=int, help="Specific issue number")
    parser.add_argument("--file", help="Read issue JSON from file")
    parser.add_argument("--apply", action="store_true", help="Apply labels")
    parser.add_argument("--comment", action="store_true", help="Add clarification comments")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be done")
    parser.add_argument("--json", action="store_true", help="Output as JSON")
    
    args = parser.parse_args()
    
    # Get issue data
    if args.file:
        with open(args.file) as f:
            data = json.load(f)
        issue_number = data.get("number")
        if not issue_number:
            print("Error: No issue number in file", file=sys.stderr)
            sys.exit(1)
        analysis = analyze_issue(args.repo, issue_number)
        if analysis:
            analysis.body = data.get("body", analysis.body)
            analysis.author = data.get("author", analysis.author)
    elif args.issue:
        analysis = analyze_issue(args.repo, args.issue)
    else:
        print("Error: Need --issue or --file", file=sys.stderr)
        sys.exit(1)
    
    if not analysis:
        sys.exit(1)
    
    # Output
    if args.json:
        output = {
            "number": analysis.number,
            "title": analysis.title,
            "author": analysis.author,
            "existing_labels": analysis.existing_labels,
            "suggested_labels": analysis.suggested_labels,
            "priority": analysis.priority,
            "confidence": analysis.confidence,
            "needs_clarification": analysis.needs_clarification,
            "clarification_questions": analysis.clarification_questions
        }
        print(json.dumps(output, indent=2))
    else:
        print(f"\n{'='*60}")
        print(f"Issue #{analysis.number}: {analysis.title}")
        print(f"Author: @{analysis.author}")
        print(f"{'='*60}")
        print(f"Existing labels: {', '.join(analysis.existing_labels) or 'none'}")
        print(f"Suggested labels: {', '.join(analysis.suggested_labels) or 'none'}")
        print(f"Priority: {analysis.priority}")
        print(f"Confidence: {analysis.confidence:.0%}")
        print(f"Needs clarification: {analysis.needs_clarification}")
        if analysis.clarification_questions:
            print(f"Questions: {analysis.clarification_questions}")
    
    # Apply actions
    if args.apply and analysis.suggested_labels:
        # Don't add labels that already exist
        new_labels = [l for l in analysis.suggested_labels 
                      if l not in analysis.existing_labels]
        if new_labels:
            apply_labels(args.repo, analysis.number, new_labels, args.dry_run)
    
    if args.comment and analysis.needs_clarification:
        comment = generate_clarification_comment(analysis.clarification_questions)
        add_comment(args.repo, analysis.number, comment, args.dry_run)


if __name__ == "__main__":
    main()
