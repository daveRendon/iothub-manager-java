#!/usr/bin/env bash

set -e
APP_HOME="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && cd .. && cd .. && pwd )/"
source "$APP_HOME/scripts/git/.functions.sh"

cd $APP_HOME
echo "Current folder: `pwd`"

if git rev-parse --verify HEAD >/dev/null 2>&1 ; then
    against=HEAD
else
    # Initial commit: diff against an empty tree object
    against=4b825dc642cb6eb9a060e54bf8d69288fbee4904
fi

check_filenames() {
    set +e
    header "Checking filenames..."

    # Redirect output to stderr.
    exec 1>&2

    # Cross platform projects tend to avoid non-ASCII filenames; prevent
    # them from being added to the repository. We exploit the fact that the
    # printable range starts at the space character and ends with tilde.
    # Note that the use of brackets around a tr range is ok here, (it's
    # even required, for portability to Solaris 10's /usr/bin/tr), since
    # the square bracket bytes happen to fall in the designated range.
    if test $(git diff --cached --name-only --diff-filter=A -z $against | LC_ALL=C tr -d '[ -~]\0' | wc -c) != 0 ; then
        error "Attempt to add a non-ASCII file name. This can cause problems on other platforms."
        exit 1
    fi

    # If there are whitespace errors, print the offending file names and fail.
    git diff-index --check --cached $against --
    set -e
}

check_donotcommit() {
    header "Checking diff for 'DONOTCOMMIT' comments..."

    set +e
    diffstr=`git diff --cached $against | grep -ie '^\+.*DONOTCOMMIT.*$'`
    if [[ -n "$diffstr" ]]; then
        error "You have left DONOCOMMIT in your changes, you can't commit until it has been removed."
        exit 1
    fi
    set -e
}

verify_dotnet() {
    header "Checking .NET Core code..."

    cd $APP_HOME/dotnet
    ./scripts/build
    if [ $? -ne 0 ]; then
        error "Some .NET Core unit tests failed."
        exit 1
    fi
}

verify_dotnet4x() {
    header "Checking .NET Framework code..."

    cd $APP_HOME/dotnet4x
    ./scripts/build
    if [ $? -ne 0 ]; then
        error "Some .NET Framework unit tests failed."
        exit 1
    fi
}

verify_java() {
    header "Checking Java code..."

    cd $APP_HOME/java
    if test $(./gradlew check | grep "BUILD SUCCESSFUL" | wc -l) != 1 ; then
        error "Some Java unit tests failed."
        ./gradlew check --info
        exit 1
    fi
}

verify_in_parallel() {
    header "Checking code... [running tests in the background]"

    set +e

    verify_dotnet 1>/dev/null 2>&1 &
    pid1=$!

    verify_dotnet4x 1>/dev/null 2>&1 &
    pid2=$!

    verify_java 1>/dev/null 2>&1 &
    pid3=$!

    wait $pid1
    err1=$?
    wait $pid2
    err2=$?
    wait $pid3
    err3=$?
    set -e

    if [ $err1 -eq 0 ]; then 
        echo ".NET Core: PASSED"
    else
        error ".NET Core: FAILED"
    fi

    if [ $err2 -eq 0 ]; then 
        echo ".NET Framework: PASSED"
    else
        error ".NET Framework: FAILED"
    fi

    if [ $err3 -eq 0 ]; then 
        echo "Java: PASSED"
    else
        error "Java: FAILED"
    fi

    if [ $err1 -ne 0 -o $err2 -ne 0 ]; then
        exit 1
    fi
}

check_filenames
check_donotcommit
#verify_in_parallel
verify_dotnet
verify_dotnet4x
verify_java
