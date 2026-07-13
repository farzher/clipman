LRU :: struct(KEY_TYPE: Type, VALUE_TYPE: Type, ENTRY_COUNT: u8, FREE_PROC: (*VALUE_TYPE)->()=null ) {
  entries: Soa(Entry, ENTRY_COUNT);
  next_index: u8 = ENTRY_COUNT-1;

  Entry :: struct {key: KEY_TYPE; value: VALUE_TYPE;}
}

lru_free :: (lru: *LRU) {
  assert(xx lru.FREE_PROC);

  lru.next_index = lru.ENTRY_COUNT-1;
  for i: 0 .. lru.ENTRY_COUNT-1 {
    if lru.entries.key[i] == 0 continue;
    // something exists here. free it
    lru.entries.key[i] = 0;
    lru.FREE_PROC(*lru.entries.value[i]);
  }
}

add :: (lru: *LRU, key: lru.KEY_TYPE, value: lru.VALUE_TYPE) -> *lru.VALUE_TYPE {
  assert(key != 0); // currently a key of 0 isn't valid because that means it's an empty slot

  #if lru.FREE_PROC {
    if lru.entries.key[lru.next_index] != 0 then lru.FREE_PROC(*lru.entries.value[lru.next_index]);
  }

  value_ptr := *lru.entries.value[lru.next_index];
  lru.entries.key[lru.next_index] = key;
  lru.entries.value[lru.next_index] = value;

  if lru.next_index == 0 then lru.next_index = lru.ENTRY_COUNT-1;
  else lru.next_index -= 1;

  return value_ptr;
}

find_pointer :: inline (lru: LRU, key: lru.KEY_TYPE) -> *lru.VALUE_TYPE {
  for i: 1 .. lru.ENTRY_COUNT {
    index := (lru.next_index+i) % lru.ENTRY_COUNT;
    if key == lru.entries.key[index] then return *lru.entries.value[index];
  }
  return null;
}

#import "Basic";
#import "Soa";
