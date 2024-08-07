#!/bin/bash
set -e  # 스크립트 실행 중 오류가 발생하면 즉시 종료

export file=$1  # 첫 번째 인자를 변수 file에 저장

# 오류 발생 시 실행될 함수
error_handler() {
    errcode=$?  # trap 함수가 실행될 때의 종료 코드를 저장
    echo "error $errcode"
    echo "The command executing at the time of the error was: $BASH_COMMAND"
    echo "on line ${BASH_LINENO[0]}"
    # 오류 처리, 정리, 로깅, 알림 수행
    # 스택 종료...
    docker compose -f $file down -v --remove-orphans  # docker compose 스택 종료 및 고아 컨테이너 제거
    exit $errcode  # 스크립트 종료
}
trap error_handler ERR  # 오류 발생 시 error_handler 함수 실행

# 모든 컨테이너가 정상적으로 실행 중인지 확인하는 함수
all_great() {
    echo "Verifying Process"
    running=$(docker compose -f $1 ps | grep Up | wc -l)  # 실행 중인 컨테이너 개수 확인
    if [ "$running" != "$2" ]; then  # 실행 중인 컨테이너 개수가 예상과 다르면
        docker compose -f $1 ps  # 실행 중인 컨테이너 목록 출력
        docker compose -f $1 logs  # 컨테이너 로그 출력
        exit 1  # 스크립트 종료
    fi
}

# Kafka 테스트 함수
kafka_tests() {
    echo "Testing Kafka"
    topic="testtopic"
    if grep -q kafka3 $1; then replication_factor="3"; else replication_factor="1"; fi  # kafka3이 포함된 경우 복제 인수를 3으로 설정
    for i in 1 2 3 4 5; do
        echo "Trying to create test topic" &&
        docker exec kafka1 kafka-topics --create --topic $topic --replication-factor $replication_factor --partitions 12 --bootstrap-server kafka1:9092 &&
        break || sleep 5  # 테스트 토픽 생성 시도, 실패 시 5초 대기
    done
    sleep 5
    for x in {1..100}; do echo $x; done | docker exec -i kafka1 kafka-console-producer --broker-list kafka1:9092 --topic $topic  # 테스트 메시지 전송
    sleep 5
    rows=$(docker exec kafka1 kafka-console-consumer --bootstrap-server kafka1:9092 --topic $topic --from-beginning --timeout-ms 10000 | wc -l)  # 메시지 수신 및 개수 확인
    if [ "$rows" != "100" ]; then  # 수신된 메시지 개수가 100개가 아니면
        docker exec kafka1 kafka-console-consumer --bootstrap-server kafka1:9092 --topic $topic --from-beginning --timeout-ms 10000 | wc -l
        exit 1  # 스크립트 종료
    else
        echo "Kafka Test Success"  # Kafka 테스트 성공
    fi
}

# 스택 생성
docker compose -f $file down -v --remove-orphans  # 기존 스택 종료 및 볼륨 제거, 고아 컨테이너 제거
docker compose -f $file up -d  # 새 스택 백그라운드 실행
sleep 30  # 30초 대기
docker compose -f $file ps  # 실행 중인 컨테이너 목록 출력
all_great $1 $2  # 스택 상태 확인
kafka_tests $1  # Kafka 테스트
all_great $1 $2  # 스택 상태 재확인
docker compose -f $file down -v --remove-orphans  # 스택 종료 및 볼륨 제거, 고아 컨테이너 제거
echo "Success!"  # 스크립트 성공 메시지 출력
