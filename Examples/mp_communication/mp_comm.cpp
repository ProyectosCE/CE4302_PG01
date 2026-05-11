// compile: g++ --std=c++17 -Wall -Wextra mp_comm.cpp -o  mp_comm
// run $> ./mp_comm
#include <iostream>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <chrono>

// Shared resources
std::mutex mtx;
std::condition_variable cv;
bool data_ready = false;
int shared_memory[16];

void producer() {
    // Simulate data production
    std::this_thread::sleep_for(std::chrono::seconds(1));
 
    {
        std::lock_guard<std::mutex> lock(mtx);
        shared_memory[0] = (rand() % 20);  // Write to shared memory
        data_ready = true;
        std::cout << "Producer: Data written " <<  shared_memory[0] << "\n";
    }
    cv.notify_one();  // Notify consumer
}

void consumer() {
    std::unique_lock<std::mutex> lock(mtx);
    cv.wait(lock, []{ return data_ready; });  // Wait for data
    
    std::cout << "Consumer: Received data: " << shared_memory[0] << "\n";
    // Reset for potential reuse
    data_ready = false;
}

int main() {
    std::thread producer_thread(producer);
    std::thread consumer_thread(consumer);

    producer_thread.join();
    consumer_thread.join();

    return 0;
}