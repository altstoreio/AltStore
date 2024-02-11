//
//  fragmentzip.h
//  AltStore
//
//  Created by Riley Testut on 10/25/21.
//  Copyright © 2021 Riley Testut. All rights reserved.
//

#ifndef fragmentzip_h
#define fragmentzip_h

typedef void fragmentzip_t;
typedef void (*fragmentzip_process_callback_t)(unsigned int progress);
fragmentzip_t *fragmentzip_open(const char *url);
int fragmentzip_download_file(fragmentzip_t *info, const char *remotepath, const char *savepath, fragmentzip_process_callback_t callback);
void fragmentzip_close(fragmentzip_t *info);

#endif /* fragmentzip_h */
