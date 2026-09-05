#!/bin/zsh

side_thread_id="side-test-thread"

while IFS= read -r message; do
    method=$(print -r -- "$message" | jq -r '.method // ""')
    request_id=$(print -r -- "$message" | jq -r '.id // ""')

    case "$method" in
        initialize)
            print -r -- "{\"id\":$request_id,\"result\":{}}"
            ;;
        thread/list)
            print -r -- "{\"id\":$request_id,\"result\":{\"data\":[{\"id\":\"test-thread\",\"name\":\"Scanner test\",\"cwd\":\"/tmp/CodexStatusFixture\",\"updatedAt\":1788556800,\"status\":{\"type\":\"active\",\"activeFlags\":[]}}]}}"
            ;;
        account/rateLimits/read)
            if [[ "${FAKE_RATE_LIMIT_PROFILE:-dual}" == "weekly-only" ]]; then
                print -r -- "{\"id\":$request_id,\"result\":{\"rateLimits\":{\"limitId\":\"codex\",\"primary\":{\"usedPercent\":5,\"windowDurationMins\":10080,\"resetsAt\":1789189372},\"secondary\":null,\"planType\":\"pro\"},\"rateLimitsByLimitId\":{\"codex\":{\"limitId\":\"codex\",\"primary\":{\"usedPercent\":5,\"windowDurationMins\":10080,\"resetsAt\":1789189372},\"secondary\":null},\"codex_bengalfox\":{\"limitId\":\"codex_bengalfox\",\"limitName\":\"GPT-5.3-Codex-Spark\",\"primary\":{\"usedPercent\":0,\"windowDurationMins\":300,\"resetsAt\":1788617101},\"secondary\":{\"usedPercent\":0,\"windowDurationMins\":10080,\"resetsAt\":1789203901}}}}}"
            else
                print -r -- "{\"id\":$request_id,\"result\":{\"rateLimits\":{\"limitId\":\"codex\",\"primary\":{\"usedPercent\":20,\"windowDurationMins\":300,\"resetsAt\":1788560400},\"secondary\":{\"usedPercent\":35,\"windowDurationMins\":10080,\"resetsAt\":1789161600},\"planType\":\"plus\"},\"rateLimitsByLimitId\":{\"codex\":{\"limitId\":\"codex\",\"primary\":{\"usedPercent\":20,\"windowDurationMins\":300,\"resetsAt\":1788560400},\"secondary\":{\"usedPercent\":35,\"windowDurationMins\":10080,\"resetsAt\":1789161600}},\"codex_bengalfox\":{\"limitId\":\"codex_bengalfox\",\"limitName\":\"GPT-5.3-Codex-Spark\",\"primary\":{\"usedPercent\":90,\"windowDurationMins\":300,\"resetsAt\":1788560500}}}}}"
            fi
            ;;
        thread/fork)
            source_id=$(print -r -- "$message" | jq -r '.params.threadId // ""')
            ephemeral=$(print -r -- "$message" | jq -r '.params.ephemeral // false')
            sandbox=$(print -r -- "$message" | jq -r '.params.sandbox // ""')
            approval=$(print -r -- "$message" | jq -r '.params.approvalPolicy // ""')
            deferred_goal=$(print -r -- "$message" | jq -r '.params.deferGoalContinuation // ""')
            if [[ "$source_id" == "test-thread" && "$ephemeral" == "true" && "$sandbox" == "read-only" && "$approval" == "never" && -z "$deferred_goal" ]]; then
                print -r -- "{\"id\":$request_id,\"result\":{\"thread\":{\"id\":\"$side_thread_id\",\"ephemeral\":true}}}"
            else
                print -r -- "{\"id\":$request_id,\"error\":{\"message\":\"fork must be ephemeral and read-only\"}}"
            fi
            ;;
        turn/start)
            thread_id=$(print -r -- "$message" | jq -r '.params.threadId // ""')
            prompt=$(print -r -- "$message" | jq -r '.params.input[0].text // ""')
            trigger=$(print -r -- "$message" | jq -r '.params.turnTrigger // ""')
            if [[ "$thread_id" == "$side_thread_id" && -n "$prompt" && "$trigger" == "codexstatus-progress-sidecar" ]]; then
                print -r -- "{\"id\":$request_id,\"result\":{\"turn\":{\"id\":\"test-turn\"}}}"
                print -r -- "{\"method\":\"item/completed\",\"params\":{\"threadId\":\"$side_thread_id\",\"turnId\":\"test-turn\",\"item\":{\"id\":\"answer\",\"type\":\"agentMessage\",\"text\":\"Stage: implementation\\nCurrent: temporary side conversation is working\\nNext: local test\"}}}"
                print -r -- "{\"method\":\"turn/completed\",\"params\":{\"threadId\":\"$side_thread_id\",\"turn\":{\"id\":\"test-turn\"}}}"
            else
                print -r -- "{\"id\":$request_id,\"error\":{\"message\":\"invalid sidecar request\"}}"
            fi
            ;;
    esac
done
