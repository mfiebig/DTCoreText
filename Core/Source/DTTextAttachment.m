//
//  DTTextAttachment.m
//  DTCoreText
//
//  Created by Oliver on 14.01.11.
//  Copyright 2011 Drobnik.com. All rights reserved.
//

#import "DTTextAttachment.h"
#import "DTCoreText.h"
#import "DTUtils.h"

#import "DTBase64Coding.h"

static NSCache *imageCache = nil;

@interface DTTextAttachment ()

+ (NSCache *)sharedImageCache;

@end

@implementation DTTextAttachment
{
	CGSize _originalSize;
	CGSize _displaySize;
	DTTextAttachmentVerticalAlignment _verticalAlignment;
	id _contents;
    NSDictionary *_attributes;
    
    DTTextAttachmentType _contentType;
	
	NSURL *_contentURL;
	
	NSURL *_hyperLinkURL;
	NSString *_hyperLinkGUID;
	
	CGFloat _fontLeading;
	CGFloat _fontAscent;
	CGFloat _fontDescent;
}

+ (NSCache *)sharedImageCache {
  if (imageCache) return imageCache;

  static dispatch_once_t onceToken; // lock
  dispatch_once(&onceToken, ^{ // this block run only once
		imageCache = [[NSCache alloc] init];
  });
  return imageCache;
}

+ (DTTextAttachment *)textAttachmentWithElement:(DTHTMLElement *)element options:(NSDictionary *)options
{
	// determine type
	DTTextAttachmentType attachmentType;
	
	if ([element.name isEqualToString:@"img"])
	{
		attachmentType = DTTextAttachmentTypeImage;
	}
	else if ([element.name isEqualToString:@"video"])
	{
		attachmentType = DTTextAttachmentTypeVideoURL;
	}
	else if ([element.name isEqualToString:@"iframe"])
	{
		attachmentType = DTTextAttachmentTypeIframe;
	}
	else if ([element.name isEqualToString:@"object"])
	{
		attachmentType = DTTextAttachmentTypeObject;
	}
	else
	{
		return nil;
	}
	
	// determine if there is a display size restriction
	CGSize maxImageSize = CGSizeZero;
	
	NSValue *maxImageSizeValue =[options objectForKey:DTMaxImageSize];
	if (maxImageSizeValue)
	{
#if TARGET_OS_IPHONE
		maxImageSize = [maxImageSizeValue CGSizeValue];
#else
		maxImageSize = [maxImageSizeValue sizeValue];
#endif
	}
	
	// width, height from tag
	CGSize displaySize = element.size; // width/height from attributes or CSS style
	CGSize originalSize = element.size;
	
	// get base URL
	NSURL *baseURL = [options objectForKey:NSBaseURLDocumentOption];
	
	// decode URL
	NSString *src = [element.attributes objectForKey:@"src"];
	
	NSURL *contentURL = nil;
	DTImage *decodedImage = nil;
	
	
	// decode content URL
	if ([src length]) // guard against img with no src
	{ 
		if ([src hasPrefix:@"data:"])
		{
			NSString *cleanStr = [[src componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] componentsJoinedByString:@""];
			
			NSURL *dataURL = [NSURL URLWithString:cleanStr];
			
			// try native decoding first
			NSData *decodedData = [NSData dataWithContentsOfURL:dataURL];
			
			// try own base64 decoding
			if (!decodedData)
			{
				NSRange range = [cleanStr rangeOfString:@"base64,"];
				
				if (range.length)
				{
					NSString *encodedData = [cleanStr substringFromIndex:range.location + range.length];
					
					decodedData = [DTBase64Coding dataByDecodingString:encodedData];
				}
			}
			
			// if we have image data, get the default display size
			if (decodedData)
			{
				decodedImage = [[DTImage alloc] initWithData:decodedData];
				
				if (!displaySize.width || !displaySize.height)
				{
					displaySize = decodedImage.size;
				}
			}
		}
		else // normal URL
		{
			contentURL = [NSURL URLWithString:src];
			
			if(!contentURL)
			{
				src = [src stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
				contentURL = [NSURL URLWithString:src relativeToURL:baseURL];
			}
			
			if (![contentURL scheme])
			{
				// possibly a relative url
				if (baseURL)
				{
					contentURL = [NSURL URLWithString:src relativeToURL:baseURL];
				}
				else
				{
					// file in app bundle
					NSBundle *bundle = [NSBundle mainBundle];
					NSString *path = [bundle pathForResource:src ofType:nil];
					
					if (path)
					{
						// Prevent a crash if path turns up nil.
						contentURL = [NSURL fileURLWithPath:path];   
					}
					else
					{
						// might also be in a different bundle, e.g. when unit testing
						bundle = [NSBundle bundleForClass:[DTTextAttachment class]];
						
						path = [bundle pathForResource:src ofType:nil];
						if (path)
						{
							// Prevent a crash if path turns up nil.
							contentURL = [NSURL fileURLWithPath:path];
						}
					}
				}
			}
		}
	}
	
	DTTextAttachment *attachment = [[DTTextAttachment alloc] init];
	
	// for local images we can get their size by inspecting them
	if (attachmentType == DTTextAttachmentTypeImage)
	{
		// if it's a local file we need to inspect it to get it's dimensions
		if (!displaySize.width || !displaySize.height)
		{
			// let's check if we have a cached image already then we can inspect that
			DTImage *image = [[DTTextAttachment sharedImageCache] objectForKey:[contentURL absoluteString]];
			
			if (!image)
			{
				// only local files we can directly load without punishment
				if ([contentURL isFileURL])
				{
					image = [[DTImage alloc] initWithContentsOfFile:[contentURL path]];
				}
				
				// cache that for later
				if (image)
				{
					[[DTTextAttachment sharedImageCache] setObject:image forKey:[contentURL absoluteString]];
				}
			}
			
			// we have an image, so we can set the original size and default display size
			if (image)
			{
				originalSize = image.size;
				
				// initial display size matches original
				displaySize = originalSize;
			}
		}
	}
	
	// if you have no display size we assume original size
	if (CGSizeEqualToSize(displaySize, CGSizeZero))
	{
		displaySize = originalSize;
	}
	
	// adjust the display size if there is a restriction and it's too large
	CGSize adjustedSize = displaySize;
	
	if (!CGSizeEqualToSize(maxImageSize, CGSizeZero))
	{
		if (maxImageSize.width < displaySize.width || maxImageSize.height < displaySize.height)
		{
			adjustedSize = sizeThatFitsKeepingAspectRatio(displaySize, maxImageSize);
		}
	}
		
	attachment.contentType = attachmentType;
	attachment.contentURL = contentURL;
	attachment.contents = decodedImage;
	attachment.originalSize = originalSize;
	attachment.displaySize = adjustedSize;
	attachment.attributes = element.attributes;
	
	return attachment;
}


// makes a data URL of the image
- (NSString *)dataURLRepresentation
{
	if ((_contents==nil) || _contentType != DTTextAttachmentTypeImage)
	{
		return nil;
	}
	
	DTImage *image = (DTImage *)_contents;
	NSData *data = [image dataForPNGRepresentation];
	NSString *encoded = [DTBase64Coding stringByEncodingData:data];
	
	return [@"data:image/png;base64," stringByAppendingString:encoded];
}

- (void)adjustVerticalAlignmentForFont:(CTFontRef)font
{
	_fontLeading = CTFontGetLeading(font);
	_fontAscent = CTFontGetAscent(font);
	_fontDescent = CTFontGetDescent(font);
}

- (CGFloat)ascentForLayout
{
	switch (_verticalAlignment) 
	{
		case DTTextAttachmentVerticalAlignmentBaseline:
		{
			return _displaySize.height;
		}
		case DTTextAttachmentVerticalAlignmentTop:
		{
			return _fontAscent;
		}	
		case DTTextAttachmentVerticalAlignmentCenter:
		{
			CGFloat halfHeight = (_fontAscent + _fontDescent) / 2.0f;
			
			return halfHeight - _fontDescent + _displaySize.height/2.0f;
		}
		case DTTextAttachmentVerticalAlignmentBottom:
		{
			return _displaySize.height - _fontDescent;
		}
	}
}

- (CGFloat)descentForLayout
{
	switch (_verticalAlignment) 
	{
		case DTTextAttachmentVerticalAlignmentBaseline:
		{
			return 0;
		}	
		case DTTextAttachmentVerticalAlignmentTop:
		{
			return _displaySize.height - _fontAscent;
		}	
		case DTTextAttachmentVerticalAlignmentCenter:
		{
			CGFloat halfHeight = (_fontAscent + _fontDescent) / 2.0f;
			
			return halfHeight - _fontAscent + _displaySize.height/2.0f;
		}	
		case DTTextAttachmentVerticalAlignmentBottom:
		{
			return _fontDescent;
		}
	}
}

#pragma mark Properties
/** Mutator for originalSize. Sets displaySize to the same value as originalSize. 
 @param The CGSize to store in originalSize. */
- (void)setOriginalSize:(CGSize)originalSize
{
	_originalSize = originalSize;
	self.displaySize = _originalSize;
}

- (void)setDisplaySize:(CGSize)displaySize withMaxDisplaySize:(CGSize)maxDisplaySize
{
	if (_originalSize.width && _originalSize.height)
	{
		// width and/or height missing
		if (displaySize.width==0 && displaySize.height==0)
		{
			displaySize = _originalSize;
		}
		else if (!displaySize.width && displaySize.height)
		{
			// width missing, calculate it
			CGFloat factor = _originalSize.height / displaySize.height;
			displaySize.width = roundf(_originalSize.width / factor);
		}
		else if (displaySize.width>0 && displaySize.height==0)
		{
			// height missing, calculate it
			CGFloat factor = _originalSize.width / displaySize.width;
			displaySize.height = roundf(_originalSize.height / factor);
		}
	}
	
	if (maxDisplaySize.width>0 && maxDisplaySize.height>0)
	{
		if (maxDisplaySize.width < displaySize.width || maxDisplaySize.height < displaySize.height)
		{
			displaySize = sizeThatFitsKeepingAspectRatio(displaySize, maxDisplaySize);
		}
	}
	
	_displaySize = displaySize;
}

/**
 Accessor for the contents instance variable. If the content type is DTTextAttachmentTypeImage this returns a DTImage instance of the contents.
 @returns Contents. If it is an image, a DTImage instance is returned. Otherwise it is returned as is. 
 */
- (id)contents
{
	if (!_contents)
	{
		if (_contentType == DTTextAttachmentTypeImage && _contentURL)
		{
			DTImage *image = [[DTTextAttachment sharedImageCache] objectForKey:[_contentURL absoluteString]];
			
			// only local files can be loaded into cache
			if (!image && [_contentURL isFileURL])
			{
				image = [[DTImage alloc] initWithContentsOfFile:[_contentURL path]];
				
				// cache it
				if (image)
				{
					[[DTTextAttachment sharedImageCache] setObject:image forKey:[_contentURL absoluteString]];
				}
			}

			return image;
		}
	}
	
	return _contents;
}

@synthesize originalSize = _originalSize;
@synthesize displaySize = _displaySize;
@synthesize contents = _contents;
@synthesize contentType = _contentType;
@synthesize contentURL = _contentURL;
@synthesize hyperLinkURL = _hyperLinkURL;
@synthesize attributes = _attributes;
@synthesize verticalAlignment = _verticalAlignment;
@synthesize hyperLinkGUID = hyperLinkGUID;
@synthesize childNodes = _childNodes;

@end
