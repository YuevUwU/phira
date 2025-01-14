# This junk code is modified by AI-generated code by ChatGPT
import subprocess
import re
import os

FLUENT_PATTERN = re.compile(r"^(?P<key>[\w-]+)\s*=\s*(?P<value>.*)", re.MULTILINE)

def report(parent_dir, source_lang, target_lang):

    def run_command(cmd):
        result = subprocess.run(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        return result.stdout.strip()

    def extract_fluent(text: str, return_type: str = "dict") -> dict | tuple:
        result = {}
        matches = FLUENT_PATTERN.findall(text)

        for k, v in matches:
            result[k] = v

        match return_type:
            case "dict":
                return result
            case "tuple":
                return (
                    tuple(result.items()) if result.__len__() > 0 else ((None, None),)
                )
            case _:
                ValueError()

    def extract_fluent_strings(diff_text: str):
        changes = {}
        current_key = None
        for line in diff_text.splitlines():
            if line.startswith("-") or line.startswith("+"):
                key, value = extract_fluent(line[1:].strip(), "tuple")[0]
                if key is not None:
                    if changes.get(key) is None:
                        current_key = key
                        changes[key] = {
                            "old": None,
                            "new": None,
                            "old_line": None,
                            "new_line": None,
                        }
                    if line.startswith("-"):
                        changes[key]["old"] = value
                        changes[key]["old_line"] = line.strip()
                    elif line.startswith("+"):
                        changes[key]["new"] = value
                        changes[key]["new_line"] = line.strip()
        return changes

    def log_changes(relative_path, key, source_lang_translation, target_lang_translation, commit):
        print("```plaintext")
        print(f"{relative_path} - {key} - {commit[:7]}")
        print(f"{source_lang}: {source_lang_translation}  ")
        print(f"{target_lang}: {target_lang_translation}  ")
        print("```")

    def get_file_paths(directory):

        file_paths = []
        for root, _, files in os.walk(directory):
            for file in files:
                if file.endswith(".ftl"):
                    file_paths.append(os.path.join(root, file))
        return file_paths

    def compare_keys(a_lang_files, b_lang_files, a_lang_dir, b_lang_dir):

        key_diff = {}

        for a_lang_file in a_lang_files:
            a_lang_content = open(a_lang_file).read()
            a_lang_keys = set(extract_fluent(a_lang_content).keys())
            relative_path = os.path.relpath(a_lang_file, a_lang_dir)
            b_lang_file = os.path.join(b_lang_dir, relative_path)

            if os.path.exists(b_lang_file):
                b_lang_content = open(b_lang_file).read()
                b_lang_keys = set(extract_fluent(b_lang_content).keys())

                key_diff[relative_path] = a_lang_keys - b_lang_keys

        return key_diff

    def log_diff(diff_keys, title, redirect_lang_dir):
        print(title)
        for relative_path, keys in diff_keys.items():
            for key in keys:
                print(f"[{relative_path}](https://github.com/TeamFlos/phira/tree/main/{source_lang_dir}/{relative_path}) - {key}  ")

    def print_append_needed():
        target_lang_files = get_file_paths(target_lang_dir)
        source_lang_files = get_file_paths(source_lang_dir)

        key_diff = compare_keys(
            source_lang_files, target_lang_files, source_lang_dir, target_lang_dir
        )

        if any(len(v) != 0 for v in key_diff.values()):
            log_diff(key_diff, "#### Append needed", source_lang_dir)

    def print_delete_needed():
        target_lang_files = get_file_paths(target_lang_dir)
        source_lang_files = get_file_paths(source_lang_dir)

        key_diff = compare_keys(
            target_lang_files, source_lang_files, target_lang_dir, source_lang_dir
        )

        if any(len(v) != 0 for v in key_diff.values()):
            log_diff(key_diff, "#### Delete needed", target_lang_dir)

    def print_edited_translations():
        print("#### May need Edit")
        may_changed = set()

        source_lang_translations, target_lang_translations = dict(), dict()
        source_lang_files = get_file_paths(source_lang_dir)
        target_lang_files = get_file_paths(target_lang_dir)

        for source_lang_file in source_lang_files:
            source_lang_content = open(source_lang_file).read()
            relative_path = os.path.relpath(source_lang_file, source_lang_dir)
            source_lang_translations[relative_path] = extract_fluent(
                source_lang_content
            )

        for target_lang_file in target_lang_files:
            target_lang_content = open(target_lang_file).read()
            relative_path = os.path.relpath(target_lang_file, target_lang_dir)
            target_lang_translations[relative_path] = extract_fluent(
                target_lang_content
            )

        commits = run_command(["git", "rev-list", "--all"]).splitlines()
        # commits.remove("9ccfd2a71c0309bdd0a8b368428259224ac6515b")
        for commit in commits:

            diff_command = [
                "git",
                "diff-tree",
                "--no-commit-id",
                "--unified=0",
                "-r",
                "-p",
                commit,
                "--",
                source_lang_dir,
            ]
            diff_output = run_command(diff_command)

            if not diff_output:
                continue

            file_diffs = re.split(r"diff --git", diff_output)[1:]

            for file_diff in file_diffs:
                file_lines = file_diff.strip().splitlines()
                file_path = file_lines[0].split()[1][2:]

                if file_path.endswith(".ftl"):
                    changes = extract_fluent_strings("\n".join(file_lines[1:]))

                    for key, change in changes.items():
                        if (
                            change["old"] is not None
                            and change["new"] is not None
                            and change["old"] != change["new"]
                        ):
                            relative_path = os.path.relpath(file_path, source_lang_dir)
                            may_changed.add((relative_path, key, commit))

        for relative_path, key, commit in may_changed:
            source_lang_translation = source_lang_translations[relative_path][key]
            target_lang_file: dict | None = target_lang_translations.get(relative_path)
            if target_lang_file is not None:
                target_lang_translation = target_lang_file.get(key)
            else:
                target_lang_translation = None
            log_changes(relative_path, key, source_lang_translation, target_lang_translation, commit)

    source_lang_dir = f"{parent_dir}/{source_lang}"
    target_lang_dir = f"{parent_dir}/{target_lang}"
    print(f"### {target_lang_dir}")
    print_append_needed()
    print_delete_needed()
    print_edited_translations()


if __name__ == "__main__":
    SOURCE_LANG = "zh-CN"
    TARGET_LANG = "mn-MN"

    print(f"## TODO Translation Report for {TARGET_LANG}")
    print("_**NOTICE: This report doesn't detect edited multiline text**_")
    
    report("phira/locales", SOURCE_LANG, TARGET_LANG)
    report("prpr/locales", SOURCE_LANG, TARGET_LANG)
