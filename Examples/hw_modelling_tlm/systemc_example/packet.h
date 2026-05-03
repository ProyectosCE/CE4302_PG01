#ifndef PACKET_H
#define PACKET_H

#include <iostream>

struct Packet {
    int source_id;
    int dest_id;
    int data;

    friend std::ostream& operator<<(std::ostream& os, const Packet& p) {
        os << "[SRC: " << p.source_id << " | DST: " << p.dest_id << " | Data: " << p.data << "]";
        return os;
    }
};

#endif